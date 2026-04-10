@IsTest
private class CastleLeadActivityReportSvcTest {
  private static final String CONV_FIELD = 'Fecha_Conversi_n_MKT__c';

  private static void assertConversionField() {
    System.assert(
      Lead.SObjectType.getDescribe().fields.getMap().containsKey(CONV_FIELD),
      'La org de tests debe tener Lead.' + CONV_FIELD
    );
  }

  private static Lead newLeadOpen(LeadStatus openSt, Date convDate) {
    Lead ld = new Lead(LastName = 'SvcTest', Company = 'Co', Status = openSt.MasterLabel);
    ld.put(CONV_FIELD, convDate);
    return ld;
  }

  @IsTest
  static void getReport_empty_returnsZeros() {
    CastleLeadActivityReportSvc.ActivityFilterDto f = new CastleLeadActivityReportSvc.ActivityFilterDto();
    CastleLeadActivityReportSvc.ReportResultDto r = CastleLeadActivityReportSvc.getReport(f);
    System.assertEquals(0, r.ownerRowCount);
    System.assertNotEquals(null, r.rows);
    System.assertEquals(0, r.leadPoolCount);
  }

  @IsTest
  static void getReport_countsLeadWho_tasksWithPrefix_and_eventsInWindow() {
    assertConversionField();
    LeadStatus openSt = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = FALSE
      ORDER BY SortOrder NULLS LAST
      LIMIT 1
    ];

    Lead ld = newLeadOpen(openSt, Date.today());
    insert ld;
    Test.setCreatedDate(ld.Id, Datetime.now().addDays(-3));

    Datetime startEv = Datetime.newInstanceGmt(Date.today(), Time.newInstance(12, 0, 0, 0));
    Event ev = new Event(
      Subject = 'Reunión lead',
      StartDateTime = startEv,
      EndDateTime = startEv.addHours(1),
      WhoId = ld.Id,
      DurationInMinutes = 60
    );
    insert ev;

    Task tkOk = new Task(
      Subject = 'R - Llamada lead',
      WhoId = ld.Id,
      Status = 'Completed',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert tkOk;

    Task tkT = new Task(
      Subject = 'T - Otra tarea',
      WhoId = ld.Id,
      Status = 'Completed',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert tkT;

    Task tkNo = new Task(
      Subject = 'Sin prefijo',
      WhoId = ld.Id,
      Status = 'Completed',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert tkNo;

    CastleLeadActivityReportSvc.ActivityFilterDto f = new CastleLeadActivityReportSvc.ActivityFilterDto();
    CastleLeadActivityReportSvc.ReportResultDto r = CastleLeadActivityReportSvc.getReport(f);

    System.assertEquals(1, r.leadPoolCount, 'Un lead en universo');
    System.assert(r.sumTotalEvents >= 1, 'Evento en ventana');
    System.assertEquals(2, r.sumTotalTasks, 'Cuenta tareas R - y T - ');
    System.assert(r.ownerRowCount >= 1);
    System.assertEquals(1, r.rows.size(), 'Una fila propietario–lead');
    CastleLeadActivityReportSvc.OwnerLeadRowDto d0 = r.rows[0];
    System.assertEquals(String.valueOf(ld.Id), d0.leadId);
    System.assert(d0.showOwnerCell == true);
    System.assertEquals(1, d0.ownerRowSpan);
    System.assert(d0.totalEvents >= 1);
    System.assert(d0.totalTasks >= 2);
    System.assert(d0.relatedContacts != null && d0.relatedContacts.isEmpty(), 'Sin Candidato__c');
    System.assert(String.isNotBlank(d0.leadCreatedDateStr), 'Fecha creación lead');
    System.assert(String.isNotBlank(d0.leadConversionDateStr), 'Fecha conversión MKT');
  }

  @IsTest
  static void getReport_unifiesContactCandidato() {
    assertConversionField();
    LeadStatus openSt = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = FALSE
      ORDER BY SortOrder NULLS LAST
      LIMIT 1
    ];

    Account acc = new Account(Name = 'Acc Candidato');
    insert acc;

    Lead ld = newLeadOpen(openSt, Date.today());
    insert ld;
    Test.setCreatedDate(ld.Id, Datetime.now().addDays(-5));

    Contact c = new Contact(LastName = 'Cont', AccountId = acc.Id, Candidato__c = ld.Id);
    insert c;

    Task tk = new Task(
      Subject = 'R - Tarea contacto',
      WhoId = c.Id,
      Status = 'Completed',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert tk;

    Datetime startEv = Datetime.newInstanceGmt(Date.today(), Time.newInstance(15, 0, 0, 0));
    Event ev = new Event(
      Subject = 'Evt contacto',
      StartDateTime = startEv,
      EndDateTime = startEv.addHours(1),
      WhoId = c.Id,
      DurationInMinutes = 60
    );
    insert ev;

    CastleLeadActivityReportSvc.ActivityFilterDto f = new CastleLeadActivityReportSvc.ActivityFilterDto();
    CastleLeadActivityReportSvc.ReportResultDto r = CastleLeadActivityReportSvc.getReport(f);

    System.assertEquals(1, r.leadPoolCount);
    System.assert(r.sumTotalEvents >= 1);
    System.assert(r.sumTotalTasks >= 1);
    System.assertEquals(Decimal.valueOf('1.00'), r.avgTasksPerLead);
    System.assertEquals(Decimal.valueOf('1.00'), r.avgEventsPerLead);
    CastleLeadActivityReportSvc.OwnerLeadRowDto dr = r.rows[0];
    System.assert(dr.relatedContacts != null && dr.relatedContacts.size() == 1);
    System.assertEquals(String.valueOf(c.Id), dr.relatedContacts[0].contactId);
  }

  @IsTest
  static void getReport_excludesTaskBeforeLeadCreation() {
    assertConversionField();
    LeadStatus openSt = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = FALSE
      ORDER BY SortOrder NULLS LAST
      LIMIT 1
    ];

    Date conv = Date.today().addDays(90);
    Lead ld = newLeadOpen(openSt, conv);
    insert ld;
    Test.setCreatedDate(ld.Id, Datetime.now());

    Task tk = new Task(
      Subject = 'R - Antes de creación lead',
      WhoId = ld.Id,
      Status = 'Completed',
      Priority = 'Normal',
      ActivityDate = Date.today().addDays(-15)
    );
    insert tk;

    CastleLeadActivityReportSvc.ActivityFilterDto f = new CastleLeadActivityReportSvc.ActivityFilterDto();
    CastleLeadActivityReportSvc.ReportResultDto r = CastleLeadActivityReportSvc.getReport(f);

    System.assertEquals(0, r.sumTotalTasks, 'Tarea con fecha anterior a CreatedDate del lead no cuenta');
  }

  @IsTest
  static void getReport_excludesActivityOutsideWindow() {
    assertConversionField();
    LeadStatus openSt = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = FALSE
      ORDER BY SortOrder NULLS LAST
      LIMIT 1
    ];

    Date conv = Date.today().addDays(-10);
    Lead ld = newLeadOpen(openSt, conv);
    insert ld;
    Test.setCreatedDate(ld.Id, Datetime.now().addDays(-20));

    Task tkLate = new Task(
      Subject = 'R - Fuera de ventana',
      WhoId = ld.Id,
      Status = 'Completed',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert tkLate;

    CastleLeadActivityReportSvc.ActivityFilterDto f = new CastleLeadActivityReportSvc.ActivityFilterDto();
    CastleLeadActivityReportSvc.ReportResultDto r = CastleLeadActivityReportSvc.getReport(f);

    System.assertEquals(1, r.leadPoolCount);
    System.assertEquals(0, r.sumTotalTasks, 'ActivityDate posterior a conversión no cuenta');
  }
}
