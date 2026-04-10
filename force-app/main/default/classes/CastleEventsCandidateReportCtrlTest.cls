@IsTest
private class CastleEventsCandidateReportCtrlTest {
  private static final String CONV_FIELD = 'Fecha_Conversi_n_MKT__c';

  @IsTest
  static void getLeadActivityReport_delegates_withRows() {
    System.assert(
      Lead.SObjectType.getDescribe().fields.getMap().containsKey(CONV_FIELD),
      'La org de tests debe tener Lead.' + CONV_FIELD
    );
    LeadStatus openSt = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = FALSE
      ORDER BY SortOrder NULLS LAST
      LIMIT 1
    ];
    Lead ld = new Lead(LastName = 'CtrlLead', Company = 'Co', Status = openSt.MasterLabel);
    ld.put(CONV_FIELD, Date.today());
    insert ld;
    Test.setCreatedDate(ld.Id, Datetime.now().addDays(-2));

    Datetime startEv = Datetime.newInstanceGmt(Date.today(), Time.newInstance(9, 0, 0, 0));
    Event ev = new Event(
      Subject = 'Ctrl ev',
      StartDateTime = startEv,
      EndDateTime = startEv.addHours(1),
      WhoId = ld.Id,
      DurationInMinutes = 60
    );
    insert ev;

    Task tk = new Task(
      Subject = 'R - Ctrl task',
      WhoId = ld.Id,
      Status = 'Completed',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert tk;

    CastleEventsCandidateReportController.ActivityFilterDto f = new CastleEventsCandidateReportController.ActivityFilterDto();
    CastleEventsCandidateReportController.ReportResultDto r = CastleEventsCandidateReportController.getLeadActivityReport(f);
    System.assertNotEquals(null, r);
    System.assertNotEquals(null, r.rows);
    System.assert(r.ownerRowCount >= 1);
    System.assert(r.sumTotalEvents >= 1);
    System.assert(r.sumTotalTasks >= 1);
  }

  @IsTest
  static void getLeadActivityReport_nullFilter_coversToSvc() {
    CastleEventsCandidateReportController.ReportResultDto r = CastleEventsCandidateReportController.getLeadActivityReport(null);
    System.assertNotEquals(null, r);
    System.assertNotEquals(null, r.rows);
  }
}
