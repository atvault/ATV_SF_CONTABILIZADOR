import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLeadActivityReport from '@salesforce/apex/CastleEventsCandidateReportController.getLeadActivityReport';

export default class CastleEventsCandidateReport extends LightningElement {
  @track rows = [];
  @track loading = false;

  @track sumTotalEvents = 0;
  @track sumTotalTasks = 0;
  @track leadPoolCount = 0;
  @track avgTasksPerLead = null;
  @track avgEventsPerLead = null;
  @track ownerRowCount = 0;

  /** Valores de lightning-input type date: YYYY-MM-DD */
  conversionDateFrom = null;
  conversionDateTo = null;
  ownerUserId = null;

  connectedCallback() {
    this.loadReport();
  }

  handleConversionFrom(e) {
    this.conversionDateFrom = e.target.value || null;
  }

  handleConversionTo(e) {
    this.conversionDateTo = e.target.value || null;
  }

  handleOwnerChange(e) {
    this.ownerUserId = e.detail.recordId || null;
  }

  applyFilters() {
    this.loadReport();
  }

  clearFilters() {
    this.conversionDateFrom = null;
    this.conversionDateTo = null;
    this.ownerUserId = null;
    this.loadReport();
  }

  async loadReport() {
    this.loading = true;
    const filters = {
      conversionDateFrom: this.conversionDateFrom,
      conversionDateTo: this.conversionDateTo,
      ownerUserId: this.ownerUserId
    };

    try {
      const result = await getLeadActivityReport({ filters });
      this.rows = (result.rows || []).map((r) => {
        const relatedContacts = Array.isArray(r.relatedContacts) ? r.relatedContacts : [];
        return {
          ...r,
          showOwnerCell: !!r.showOwnerCell,
          ownerRowSpan: r.ownerRowSpan != null ? Number(r.ownerRowSpan) : 1,
          relatedContacts,
          hasRelatedContacts: relatedContacts.length > 0
        };
      });
      this.sumTotalEvents = result.sumTotalEvents != null ? result.sumTotalEvents : 0;
      this.sumTotalTasks = result.sumTotalTasks != null ? result.sumTotalTasks : 0;
      this.leadPoolCount = result.leadPoolCount != null ? result.leadPoolCount : 0;
      this.avgTasksPerLead = result.avgTasksPerLead != null ? result.avgTasksPerLead : null;
      this.avgEventsPerLead = result.avgEventsPerLead != null ? result.avgEventsPerLead : null;
      this.ownerRowCount = result.ownerRowCount != null ? result.ownerRowCount : 0;
    } catch (err) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Error',
          message: err.body && err.body.message ? err.body.message : String(err),
          variant: 'error'
        })
      );
      this.rows = [];
      this.sumTotalEvents = 0;
      this.sumTotalTasks = 0;
      this.leadPoolCount = 0;
      this.avgTasksPerLead = null;
      this.avgEventsPerLead = null;
      this.ownerRowCount = 0;
    } finally {
      this.loading = false;
    }
  }

  get totalActivities() {
    return this.sumTotalEvents + this.sumTotalTasks;
  }

  get avgTasksLabel() {
    return this.avgTasksPerLead != null ? String(this.avgTasksPerLead) : '—';
  }

  get avgEventsLabel() {
    return this.avgEventsPerLead != null ? String(this.avgEventsPerLead) : '—';
  }

  get detailRowCount() {
    return this.rows.length;
  }
}
