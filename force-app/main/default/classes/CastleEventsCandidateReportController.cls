/**
 * Reporte de actividades (Event + Task) por propietario, unificado por lead canónico
 * (Lead WhoId o Contact.Candidato__c). Ventana por lead: creación → Fecha_Conversi_n_MKT__c.
 */
public with sharing class CastleEventsCandidateReportController {
  public class ActivityFilterDto {
    /** Fecha conversión desde (YYYY-MM-DD). Opcional. */
    @AuraEnabled
    public String conversionDateFrom { get; set; }
    /** Fecha conversión hasta inclusive (YYYY-MM-DD). Opcional. */
    @AuraEnabled
    public String conversionDateTo { get; set; }
    @AuraEnabled
    public Id ownerUserId { get; set; }
  }

  public class RelatedContactDto {
    @AuraEnabled
    public String contactId { get; set; }
    @AuraEnabled
    public String contactName { get; set; }
    @AuraEnabled
    public String contactUrl { get; set; }
  }

  public class OwnerLeadRowDto {
    @AuraEnabled
    public String rowKey { get; set; }
    @AuraEnabled
    public String ownerId { get; set; }
    @AuraEnabled
    public String ownerName { get; set; }
    @AuraEnabled
    public String ownerUrl { get; set; }
    @AuraEnabled
    public Boolean showOwnerCell { get; set; }
    @AuraEnabled
    public Integer ownerRowSpan { get; set; }
    @AuraEnabled
    public String leadId { get; set; }
    @AuraEnabled
    public String leadName { get; set; }
    @AuraEnabled
    public String leadUrl { get; set; }
    @AuraEnabled
    public String leadCreatedDateStr { get; set; }
    @AuraEnabled
    public String leadConversionDateStr { get; set; }
    @AuraEnabled
    public List<RelatedContactDto> relatedContacts { get; set; }
    @AuraEnabled
    public Integer totalEvents { get; set; }
    @AuraEnabled
    public Integer totalTasks { get; set; }
  }

  public class ReportResultDto {
    @AuraEnabled
    public List<OwnerLeadRowDto> rows { get; set; }
    @AuraEnabled
    public Integer sumTotalEvents { get; set; }
    @AuraEnabled
    public Integer sumTotalTasks { get; set; }
    @AuraEnabled
    public Integer leadPoolCount { get; set; }
    @AuraEnabled
    public Decimal avgTasksPerLead { get; set; }
    @AuraEnabled
    public Decimal avgEventsPerLead { get; set; }
    @AuraEnabled
    public Integer ownerRowCount { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static ReportResultDto getLeadActivityReport(ActivityFilterDto filters) {
    CastleLeadActivityReportSvc.ReportResultDto r = CastleLeadActivityReportSvc.getReport(toSvc(filters));
    return fromSvc(r);
  }

  private static CastleLeadActivityReportSvc.ActivityFilterDto toSvc(ActivityFilterDto f) {
    CastleLeadActivityReportSvc.ActivityFilterDto o = new CastleLeadActivityReportSvc.ActivityFilterDto();
    if (f == null) {
      return o;
    }
    if (String.isNotBlank(f.conversionDateFrom)) {
      o.conversionDateFrom = Date.valueOf(f.conversionDateFrom.trim());
    }
    if (String.isNotBlank(f.conversionDateTo)) {
      o.conversionDateTo = Date.valueOf(f.conversionDateTo.trim());
    }
    o.ownerUserId = f.ownerUserId;
    return o;
  }

  private static ReportResultDto fromSvc(CastleLeadActivityReportSvc.ReportResultDto r) {
    ReportResultDto out = new ReportResultDto();
    out.sumTotalEvents = r.sumTotalEvents;
    out.sumTotalTasks = r.sumTotalTasks;
    out.leadPoolCount = r.leadPoolCount;
    out.avgTasksPerLead = r.avgTasksPerLead;
    out.avgEventsPerLead = r.avgEventsPerLead;
    out.ownerRowCount = r.ownerRowCount;
    out.rows = new List<OwnerLeadRowDto>();
    if (r.rows != null) {
      for (CastleLeadActivityReportSvc.OwnerLeadRowDto row : r.rows) {
        OwnerLeadRowDto a = new OwnerLeadRowDto();
        a.rowKey = row.rowKey;
        a.ownerId = row.ownerId;
        a.ownerName = row.ownerName;
        a.ownerUrl = row.ownerUrl;
        a.showOwnerCell = row.showOwnerCell;
        a.ownerRowSpan = row.ownerRowSpan;
        a.leadId = row.leadId;
        a.leadName = row.leadName;
        a.leadUrl = row.leadUrl;
        a.leadCreatedDateStr = row.leadCreatedDateStr;
        a.leadConversionDateStr = row.leadConversionDateStr;
        a.relatedContacts = new List<RelatedContactDto>();
        if (row.relatedContacts != null) {
          for (CastleLeadActivityReportSvc.RelatedContactDto c : row.relatedContacts) {
            RelatedContactDto x = new RelatedContactDto();
            x.contactId = c.contactId;
            x.contactName = c.contactName;
            x.contactUrl = c.contactUrl;
            a.relatedContacts.add(x);
          }
        }
        a.totalEvents = row.totalEvents;
        a.totalTasks = row.totalTasks;
        out.rows.add(a);
      }
    }
    return out;
  }
}
