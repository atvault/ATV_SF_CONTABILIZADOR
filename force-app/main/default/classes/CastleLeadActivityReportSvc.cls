/**
 * Eventos y tareas por propietario, solo leads con Fecha_Conversi_n_MKT__c.
 * Ventana de fechas: actividad entre CreatedDate (GMT) del lead y Fecha_Conversi_n_MKT__c (inclusive por día).
 * Contact=Candidato__c se suma al mismo lead.
 * Tareas: Subject "R - " o "T - "; si ActivityDate es nulo se usa CompletedDateTime (GMT).
 */
public with sharing class CastleLeadActivityReportSvc {
  private static final String TASK_SUBJECT_PREFIX_R = 'R - ';
  private static final String TASK_SUBJECT_PREFIX_T = 'T - ';
  /**
   * Si true (fijo): solo cuenta actividad desde creación del lead hasta conversión MKT.
   * false desactiva el piso (solo tope MKT); reservado si negocio pidiera contar pre-creación.
   */
  private static final Boolean REQUIRE_ACTIVITY_ON_OR_AFTER_LEAD_CREATION = true;
  /** API name indicado por negocio (campo fecha de conversión MKT en Lead). */
  private static final String LEAD_CONVERSION_FIELD = 'Fecha_Conversi_n_MKT__c';

  public class ActivityFilterDto {
    /** Filtro: conversión del lead desde (fecha, sin hora). */
    public Date conversionDateFrom { get; set; }
    /** Filtro: conversión del lead hasta (fecha inclusive). */
    public Date conversionDateTo { get; set; }
    public Id ownerUserId { get; set; }
  }

  /** Contacto con lookup Candidato__c → Lead del universo. */
  public class RelatedContactDto {
    public String contactId { get; set; }
    public String contactName { get; set; }
    public String contactUrl { get; set; }
  }

  /**
   * Una fila de detalle: actividad de un propietario sobre un lead canónico.
   * Para rowspan en UI: primera fila del grupo tiene showOwnerCell=true y ownerRowSpan=N.
   */
  public class OwnerLeadRowDto {
    public String rowKey { get; set; }
    public String ownerId { get; set; }
    public String ownerName { get; set; }
    public String ownerUrl { get; set; }
    public Boolean showOwnerCell { get; set; }
    public Integer ownerRowSpan { get; set; }
    public String leadId { get; set; }
    public String leadName { get; set; }
    public String leadUrl { get; set; }
    /** Fecha creación del lead (solo día, GMT), yyyy-MM-dd. */
    public String leadCreatedDateStr { get; set; }
    /** Fecha_Conversi_n_MKT__c (solo día), yyyy-MM-dd. */
    public String leadConversionDateStr { get; set; }
    /** Contactos donde Candidato__c = este lead (puede haber más de uno). */
    public List<RelatedContactDto> relatedContacts { get; set; }
    public Integer totalEvents { get; set; }
    public Integer totalTasks { get; set; }
  }

  public class ReportResultDto {
    public List<OwnerLeadRowDto> rows { get; set; }
    /** Suma global de eventos (lead + contact unificado). */
    public Integer sumTotalEvents { get; set; }
    /** Suma global de tareas (lead + contact, prefijos R - y T - ). */
    public Integer sumTotalTasks { get; set; }
    /** Leads en el universo filtrado por fecha de conversión (denominador KPIs tareas/eventos por lead). */
    public Integer leadPoolCount { get; set; }
    public Decimal avgTasksPerLead { get; set; }
    public Decimal avgEventsPerLead { get; set; }
    public Integer ownerRowCount { get; set; }
  }

  private class OwnerLeadAgg {
    Integer totalEvents = 0;
    Integer totalTasks = 0;
  }

  public static ReportResultDto getReport(ActivityFilterDto filters) {
    assertCanRead();

    ReportResultDto out = new ReportResultDto();
    out.rows = new List<OwnerLeadRowDto>();
    out.sumTotalEvents = 0;
    out.sumTotalTasks = 0;
    out.leadPoolCount = 0;
    out.avgTasksPerLead = null;
    out.avgEventsPerLead = null;
    out.ownerRowCount = 0;

    Date convFrom = filters != null ? filters.conversionDateFrom : null;
    Date convTo = filters != null ? filters.conversionDateTo : null;
    Id ownerId = filters != null ? filters.ownerUserId : null;

    String leadSoql =
      'SELECT Id, Name, CreatedDate, ' +
      LEAD_CONVERSION_FIELD +
      ' FROM Lead WHERE ' +
      LEAD_CONVERSION_FIELD +
      ' != null ';
    if (convFrom != null) {
      leadSoql += ' AND ' + LEAD_CONVERSION_FIELD + ' >= :convFrom ';
    }
    if (convTo != null) {
      leadSoql += ' AND ' + LEAD_CONVERSION_FIELD + ' <= :convTo ';
    }

    List<Lead> leadRows;
    try {
      leadRows = Database.query(leadSoql);
    } catch (QueryException qe) {
      throw new AuraHandledException(
        'No se pudo leer leads (¿existe el campo ' +
        LEAD_CONVERSION_FIELD +
        '?). ' +
        qe.getMessage()
      );
    }

    if (leadRows.isEmpty()) {
      return out;
    }

    Map<Id, Lead> leadMap = new Map<Id, Lead>(leadRows);
    Set<Id> leadIds = leadMap.keySet();
    out.leadPoolCount = leadIds.size();

    Map<Id, Id> contactIdToLeadId = new Map<Id, Id>();
    Map<Id, List<Contact>> leadIdToContacts = new Map<Id, List<Contact>>();
    for (Contact c : [
      SELECT Id, Name, Candidato__c
      FROM Contact
      WHERE Candidato__c IN :leadIds AND Candidato__c != NULL
    ]) {
      contactIdToLeadId.put(c.Id, c.Candidato__c);
      if (!leadIdToContacts.containsKey(c.Candidato__c)) {
        leadIdToContacts.put(c.Candidato__c, new List<Contact>());
      }
      leadIdToContacts.get(c.Candidato__c).add(c);
    }

    Set<Id> whoIds = new Set<Id>();
    whoIds.addAll(leadIds);
    whoIds.addAll(contactIdToLeadId.keySet());

    String ownerClauseEv = ownerId != null ? ' AND OwnerId = :ownerId ' : '';
    String ownerClauseTk = ownerId != null ? ' AND OwnerId = :ownerId ' : '';

    String taskLikeR = TASK_SUBJECT_PREFIX_R + '%';
    String taskLikeT = TASK_SUBJECT_PREFIX_T + '%';

    List<Task> tasks;
    List<Event> events;
    try {
      tasks = Database.query(
        'SELECT OwnerId, WhoId, ActivityDate, CompletedDateTime FROM Task WHERE WhoId IN :whoIds AND (Subject LIKE :taskLikeR OR Subject LIKE :taskLikeT) ' +
        ownerClauseTk
      );
      events = Database.query(
        'SELECT OwnerId, WhoId, StartDateTime FROM Event WHERE WhoId IN :whoIds ' + ownerClauseEv
      );
    } catch (QueryException qe) {
      throw new AuraHandledException('No se pudo leer tareas/eventos: ' + qe.getMessage());
    }

    Map<Id, Map<Id, OwnerLeadAgg>> byOwnerThenLead = new Map<Id, Map<Id, OwnerLeadAgg>>();

    for (Task t : tasks) {
      if (t.OwnerId == null || t.WhoId == null) {
        continue;
      }
      Date taskAct = taskEffectiveActivityDate(t);
      if (taskAct == null) {
        continue;
      }
      Id leadCanon = canonicalLeadId(t.WhoId, leadMap.keySet(), contactIdToLeadId);
      if (leadCanon == null) {
        continue;
      }
      Lead wfLd = leadMap.get(leadCanon);
      if (!activityDateInLeadWindow(taskAct, wfLd)) {
        continue;
      }
      addTaskToOwnerLead(byOwnerThenLead, t.OwnerId, leadCanon);
    }

    for (Event ev : events) {
      if (ev.OwnerId == null || ev.WhoId == null || ev.StartDateTime == null) {
        continue;
      }
      Id leadCanon = canonicalLeadId(ev.WhoId, leadMap.keySet(), contactIdToLeadId);
      if (leadCanon == null) {
        continue;
      }
      Lead wfLd = leadMap.get(leadCanon);
      if (!eventStartInLeadWindow(ev.StartDateTime, wfLd)) {
        continue;
      }
      addEventToOwnerLead(byOwnerThenLead, ev.OwnerId, leadCanon);
    }

    Set<Id> ownerIds = byOwnerThenLead.keySet();
    Map<Id, String> ownerNames = new Map<Id, String>();
    for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds]) {
      ownerNames.put(u.Id, u.Name);
    }

    List<Id> ownersSorted = new List<Id>(ownerIds);
    ownersSorted.sort(new OwnerIdByNameComparator(ownerNames));

    List<OwnerLeadRowDto> flatRows = new List<OwnerLeadRowDto>();
    for (Id ow : ownersSorted) {
      Map<Id, OwnerLeadAgg> leadAggs = byOwnerThenLead.get(ow);
      List<Id> leadsSorted = new List<Id>(leadAggs.keySet());
      leadsSorted.sort(new LeadIdByNameComparator(leadMap));

      Integer span = leadsSorted.size();
      Integer i = 0;
      for (Id lid : leadsSorted) {
        OwnerLeadAgg ag = leadAggs.get(lid);
        Lead ldRow = leadMap.get(lid);
        String lname = ldRow != null && ldRow.Name != null ? ldRow.Name : '';
        OwnerLeadRowDto row = new OwnerLeadRowDto();
        row.rowKey = String.valueOf(ow) + '_' + String.valueOf(lid);
        row.ownerId = String.valueOf(ow);
        row.ownerUrl = '/' + ow;
        row.ownerName = ownerNames.containsKey(ow) ? ownerNames.get(ow) : '';
        row.leadId = String.valueOf(lid);
        row.leadUrl = '/' + lid;
        row.leadName = lname;
        if (ldRow != null) {
          row.leadCreatedDateStr = dateToIso(ldRow.CreatedDate.dateGMT());
          row.leadConversionDateStr = dateToIso(conversionToDate(ldRow));
        } else {
          row.leadCreatedDateStr = '';
          row.leadConversionDateStr = '';
        }
        row.totalEvents = ag.totalEvents;
        row.totalTasks = ag.totalTasks;
        row.showOwnerCell = (i == 0);
        row.ownerRowSpan = span;
        row.relatedContacts = buildRelatedContactsForLead(lid, leadIdToContacts);
        flatRows.add(row);
        i++;
      }
    }

    for (OwnerLeadRowDto r : flatRows) {
      out.sumTotalEvents += nz(r.totalEvents);
      out.sumTotalTasks += nz(r.totalTasks);
    }
    out.rows = flatRows;
    out.ownerRowCount = ownerIds.size();

    if (out.leadPoolCount > 0) {
      out.avgTasksPerLead = Decimal.valueOf(out.sumTotalTasks)
        .divide(Decimal.valueOf(out.leadPoolCount), 2);
      out.avgEventsPerLead = Decimal.valueOf(out.sumTotalEvents)
        .divide(Decimal.valueOf(out.leadPoolCount), 2);
    }

    return out;
  }

  private static Id canonicalLeadId(
    Id whoId,
    Set<Id> leadIds,
    Map<Id, Id> contactIdToLeadId
  ) {
    if (whoId.getSObjectType() == Lead.SObjectType && leadIds.contains(whoId)) {
      return whoId;
    }
    if (whoId.getSObjectType() == Contact.SObjectType && contactIdToLeadId.containsKey(whoId)) {
      return contactIdToLeadId.get(whoId);
    }
    return null;
  }

  private static void addTaskToOwnerLead(
    Map<Id, Map<Id, OwnerLeadAgg>> tree,
    Id ownerKey,
    Id leadCanon
  ) {
    if (!tree.containsKey(ownerKey)) {
      tree.put(ownerKey, new Map<Id, OwnerLeadAgg>());
    }
    Map<Id, OwnerLeadAgg> lm = tree.get(ownerKey);
    if (!lm.containsKey(leadCanon)) {
      lm.put(leadCanon, new OwnerLeadAgg());
    }
    lm.get(leadCanon).totalTasks++;
  }

  private static void addEventToOwnerLead(
    Map<Id, Map<Id, OwnerLeadAgg>> tree,
    Id ownerKey,
    Id leadCanon
  ) {
    if (!tree.containsKey(ownerKey)) {
      tree.put(ownerKey, new Map<Id, OwnerLeadAgg>());
    }
    Map<Id, OwnerLeadAgg> lm = tree.get(ownerKey);
    if (!lm.containsKey(leadCanon)) {
      lm.put(leadCanon, new OwnerLeadAgg());
    }
    lm.get(leadCanon).totalEvents++;
  }

  private static Date taskEffectiveActivityDate(Task t) {
    if (t.ActivityDate != null) {
      return t.ActivityDate;
    }
    if (t.CompletedDateTime != null) {
      return t.CompletedDateTime.dateGMT();
    }
    return null;
  }

  private static Boolean activityDateInLeadWindow(Date actDate, Lead ld) {
    Date endD = conversionToDate(ld);
    if (endD == null) {
      return false;
    }
    if (actDate > endD) {
      return false;
    }
    if (!REQUIRE_ACTIVITY_ON_OR_AFTER_LEAD_CREATION) {
      return true;
    }
    Date startD = ld.CreatedDate.dateGMT();
    return actDate >= startD;
  }

  private static Boolean eventStartInLeadWindow(Datetime startDt, Lead ld) {
    Date sd = startDt.dateGMT();
    Date endD = conversionToDate(ld);
    if (endD == null) {
      return false;
    }
    if (sd > endD) {
      return false;
    }
    if (!REQUIRE_ACTIVITY_ON_OR_AFTER_LEAD_CREATION) {
      return true;
    }
    Date startD = ld.CreatedDate.dateGMT();
    return sd >= startD;
  }

  private static Date conversionToDate(Lead ld) {
    Object v = ld.get(LEAD_CONVERSION_FIELD);
    if (v instanceof Date) {
      return (Date) v;
    }
    if (v instanceof Datetime) {
      return ((Datetime) v).dateGMT();
    }
    return null;
  }

  private static void assertCanRead() {
    if (!Event.SObjectType.getDescribe().isAccessible()) {
      throw new AuraHandledException('No tenés permiso para leer Eventos.');
    }
    if (!Task.SObjectType.getDescribe().isAccessible()) {
      throw new AuraHandledException('No tenés permiso para leer Tareas.');
    }
    if (!Lead.SObjectType.getDescribe().isAccessible()) {
      throw new AuraHandledException('No tenés permiso para leer Leads.');
    }
    if (!Contact.SObjectType.getDescribe().isAccessible()) {
      throw new AuraHandledException('No tenés permiso para leer Contactos.');
    }
    if (!Contact.Candidato__c.getDescribe().isAccessible()) {
      throw new AuraHandledException('No tenés permiso para leer Contact.Candidato__c.');
    }
    Map<String, Schema.SObjectField> lm = Lead.SObjectType.getDescribe().fields.getMap();
    if (!lm.containsKey(LEAD_CONVERSION_FIELD)) {
      throw new AuraHandledException('Falta el campo Lead.' + LEAD_CONVERSION_FIELD + ' en la org.');
    }
    if (!lm.get(LEAD_CONVERSION_FIELD).getDescribe().isAccessible()) {
      throw new AuraHandledException('No tenés permiso para leer Lead.' + LEAD_CONVERSION_FIELD + '.');
    }
  }

  private static Integer nz(Integer v) {
    return v != null ? v : 0;
  }

  private static String dateToIso(Date d) {
    return d == null ? '' : String.valueOf(d);
  }

  private static List<RelatedContactDto> buildRelatedContactsForLead(
    Id leadId,
    Map<Id, List<Contact>> leadIdToContacts
  ) {
    List<RelatedContactDto> out = new List<RelatedContactDto>();
    if (leadId == null || !leadIdToContacts.containsKey(leadId)) {
      return out;
    }
    List<Contact> clist = new List<Contact>(leadIdToContacts.get(leadId));
    clist.sort(new ContactNameComparator());
    for (Contact cx : clist) {
      RelatedContactDto d = new RelatedContactDto();
      d.contactId = String.valueOf(cx.Id);
      d.contactName = cx.Name != null ? cx.Name : '';
      d.contactUrl = '/' + cx.Id;
      out.add(d);
    }
    return out;
  }

  private class ContactNameComparator implements Comparator<Contact> {
    public Integer compare(Contact a, Contact b) {
      String na = a.Name != null ? a.Name.toLowerCase() : '';
      String nb = b.Name != null ? b.Name.toLowerCase() : '';
      Integer c = na.compareTo(nb);
      if (c != 0) {
        return c;
      }
      return String.valueOf(a.Id).compareTo(String.valueOf(b.Id));
    }
  }

  private class OwnerIdByNameComparator implements Comparator<Id> {
    Map<Id, String> ownerNames;
    OwnerIdByNameComparator(Map<Id, String> ownerNames) {
      this.ownerNames = ownerNames;
    }
    public Integer compare(Id a, Id b) {
      String na = ownerNames.containsKey(a) && ownerNames.get(a) != null
        ? ownerNames.get(a).toLowerCase()
        : '';
      String nb = ownerNames.containsKey(b) && ownerNames.get(b) != null
        ? ownerNames.get(b).toLowerCase()
        : '';
      return na.compareTo(nb);
    }
  }

  private class LeadIdByNameComparator implements Comparator<Id> {
    Map<Id, Lead> leadMap;
    LeadIdByNameComparator(Map<Id, Lead> leadMap) {
      this.leadMap = leadMap;
    }
    public Integer compare(Id a, Id b) {
      String na = leadMap.containsKey(a) && leadMap.get(a).Name != null
        ? leadMap.get(a).Name.toLowerCase()
        : '';
      String nb = leadMap.containsKey(b) && leadMap.get(b).Name != null
        ? leadMap.get(b).Name.toLowerCase()
        : '';
      Integer c = na.compareTo(nb);
      if (c != 0) {
        return c;
      }
      return String.valueOf(a).compareTo(String.valueOf(b));
    }
  }
}
