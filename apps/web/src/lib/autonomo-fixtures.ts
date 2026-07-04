import {
  currentQuarter,
  moneyString,
  quarterForDate,
  reviewedTypeFromDocumentType
} from "@/lib/autonomo-display";
import type {
  AutonomoCounterpartiesListResponse,
  AutonomoCounterpartyCreateRequest,
  AutonomoCounterpartyResponse,
  AutonomoCounterpartySummary,
  AutonomoDocumentDetailResponse,
  AutonomoDocumentListItem,
  AutonomoDocumentListQuery,
  AutonomoDocumentManualReviewRequest,
  AutonomoDocumentsListResponse,
  AutonomoDocumentDraftSummary,
  AutonomoIntakeMode,
  AutonomoRecordListItem,
  AutonomoRecordListQuery,
  AutonomoRecordsListResponse,
  AutonomoQuarterCurrencySummary,
  AutonomoQuarterDocumentTypeSummary,
  AutonomoQuarterSummaryResponse,
  AutonomoReviewedRecordSummary,
  AutonomoUploadCompletionResponse,
  AutonomoWorkspaceBootstrapResponse,
  AutonomoWorkspaceBusinessProfileUpdateRequest,
  AutonomoWorkspaceSummary
} from "@/lib/autonomo-types";

let workspace: AutonomoWorkspaceSummary = {
  workspaceId: "autonomo-fixture-workspace-001",
  ownerUserId: "account-av-user-fixture",
  displayName: "Marta Rojas Autonomo",
  country: "ES",
  timezone: "Europe/Madrid",
  defaultCurrency: "EUR",
  status: "active",
  businessProfile: {
    profileStatus: "complete",
    kind: "self_employed",
    legalName: "Marta Rojas",
    tradeName: "Marta Rojas Studio",
    taxId: "00000000T",
    vatId: "ES00000000T",
    country: "ES",
    fiscalAddress: "Madrid",
    updatedAt: "2026-07-01T08:00:00.000Z"
  },
  createdAt: "2026-07-01T08:00:00.000Z",
  updatedAt: "2026-07-01T08:00:00.000Z"
};

let counterparties: AutonomoCounterpartySummary[] = [
  {
    counterpartyId: "cp-supplier-gestoria-norte",
    workspaceId: workspace.workspaceId,
    kind: "supplier",
    displayName: "Gestoria Norte",
    taxId: "B88200124",
    vatId: "ESB88200124",
    country: "ES",
    notes: "Quarter filing support.",
    createdAt: "2026-07-01T08:05:00.000Z",
    updatedAt: "2026-07-01T08:05:00.000Z"
  },
  {
    counterpartyId: "cp-customer-senda-studio",
    workspaceId: workspace.workspaceId,
    kind: "customer",
    displayName: "Senda Studio",
    taxId: "B10977341",
    vatId: "ESB10977341",
    country: "ES",
    notes: null,
    createdAt: "2026-07-01T08:06:00.000Z",
    updatedAt: "2026-07-01T08:06:00.000Z"
  }
];

let documents: AutonomoDocumentListItem[] = [
  {
    documentId: "doc-needs-review-001",
    assetId: "asset-needs-review-001",
    workspaceId: workspace.workspaceId,
    status: "needs_review",
    direction: "purchase",
    documentType: "invoice",
    title: "Cloud tools invoice",
    documentDate: "2026-06-29",
    quarter: "2026-Q2",
    counterpartyId: null,
    originalFilename: "cloud-tools-june.pdf",
    contentType: "application/pdf",
    byteSize: 384120,
    source: "web_upload",
    intakeMode: "ai_intake",
    uploadedByUserId: workspace.ownerUserId,
    queueItemId: "queue-needs-review-001",
    queueStatus: "drafted",
    createdAt: "2026-07-01T08:12:00.000Z",
    updatedAt: "2026-07-01T08:24:00.000Z"
  },
  {
    documentId: "doc-drafted-002",
    assetId: "asset-drafted-002",
    workspaceId: workspace.workspaceId,
    status: "drafted",
    direction: "purchase",
    documentType: "ticket",
    title: "Train ticket",
    documentDate: "2026-06-18",
    quarter: "2026-Q2",
    counterpartyId: null,
    originalFilename: "renfe-ticket.jpg",
    contentType: "image/jpeg",
    byteSize: 928311,
    source: "ios_share",
    intakeMode: "ai_intake",
    uploadedByUserId: workspace.ownerUserId,
    queueItemId: "queue-drafted-002",
    queueStatus: "drafted",
    createdAt: "2026-07-01T08:15:00.000Z",
    updatedAt: "2026-07-01T08:27:00.000Z"
  },
  {
    documentId: "doc-reviewed-sale-003",
    assetId: "asset-reviewed-sale-003",
    workspaceId: workspace.workspaceId,
    status: "reviewed",
    direction: "sale",
    documentType: "invoice",
    title: "Senda Studio monthly retainer",
    documentDate: "2026-05-31",
    quarter: "2026-Q2",
    counterpartyId: "cp-customer-senda-studio",
    originalFilename: "invoice-senda-may.pdf",
    contentType: "application/pdf",
    byteSize: 218400,
    source: "web_upload",
    intakeMode: "ai_intake",
    uploadedByUserId: workspace.ownerUserId,
    queueItemId: "queue-reviewed-sale-003",
    queueStatus: "superseded",
    createdAt: "2026-07-01T08:18:00.000Z",
    updatedAt: "2026-07-01T08:44:00.000Z"
  },
  {
    documentId: "doc-reviewed-purchase-006",
    assetId: "asset-reviewed-purchase-006",
    workspaceId: workspace.workspaceId,
    status: "reviewed",
    direction: "purchase",
    documentType: "invoice",
    title: "Office rent June",
    documentDate: "2026-06-01",
    quarter: "2026-Q2",
    counterpartyId: "cp-supplier-gestoria-norte",
    originalFilename: "office-rent-june.pdf",
    contentType: "application/pdf",
    byteSize: 309112,
    source: "web_upload",
    intakeMode: "ai_intake",
    uploadedByUserId: workspace.ownerUserId,
    queueItemId: "queue-reviewed-purchase-006",
    queueStatus: "superseded",
    createdAt: "2026-07-01T08:21:00.000Z",
    updatedAt: "2026-07-01T08:48:00.000Z"
  },
  {
    documentId: "doc-failed-004",
    assetId: "asset-failed-004",
    workspaceId: workspace.workspaceId,
    status: "failed",
    direction: "unknown",
    documentType: "unknown",
    title: null,
    documentDate: null,
    quarter: null,
    counterpartyId: null,
    originalFilename: "blurred-receipt.webp",
    contentType: "image/webp",
    byteSize: 491112,
    source: "ios_camera",
    intakeMode: "ai_intake",
    uploadedByUserId: workspace.ownerUserId,
    queueItemId: "queue-failed-004",
    queueStatus: "failed",
    createdAt: "2026-07-01T08:20:00.000Z",
    updatedAt: "2026-07-01T08:31:00.000Z"
  },
  {
    documentId: "doc-queued-005",
    assetId: "asset-queued-005",
    workspaceId: workspace.workspaceId,
    status: "queued",
    direction: "unknown",
    documentType: "unknown",
    title: "Supplier quote forwarded from Files",
    documentDate: null,
    quarter: currentQuarter(),
    counterpartyId: null,
    originalFilename: "supplier-quote.pdf",
    contentType: "application/pdf",
    byteSize: 616448,
    source: "ios_files",
    intakeMode: "ai_intake",
    uploadedByUserId: workspace.ownerUserId,
    queueItemId: "queue-queued-005",
    queueStatus: "queued",
    createdAt: "2026-07-01T08:33:00.000Z",
    updatedAt: "2026-07-01T08:33:00.000Z"
  }
];

let drafts: Record<string, AutonomoDocumentDraftSummary> = {
  "doc-needs-review-001": {
    draftId: "draft-needs-review-001",
    documentId: "doc-needs-review-001",
    queueItemId: "queue-needs-review-001",
    processingRunId: "run-fixture-001",
    status: "proposed",
    priority: "urgent",
    recommendedAction: "review",
    extraction: {
      fieldValues: {
        direction: "purchase",
        documentType: "invoice",
        documentDate: "2026-06-29",
        quarter: "2026-Q2",
        counterpartyName: "Cloud Tools Europe",
        counterpartyId: null,
        baseAmount: "120.00",
        vatAmount: "25.20",
        totalAmount: "145.20",
        currency: "EUR",
        category: "Software",
        notes: "Needs review because counterparty is new and VAT total should be checked."
      },
      confidence: {
        overall: 0.67,
        fields: {
          totalAmount: 0.91,
          vatAmount: 0.62,
          counterpartyName: 0.58
        }
      },
      reviewReasons: ["unclear_counterparty", "unclear_totals"]
    },
    createdAt: "2026-07-01T08:23:00.000Z",
    updatedAt: "2026-07-01T08:23:00.000Z"
  },
  "doc-drafted-002": {
    draftId: "draft-drafted-002",
    documentId: "doc-drafted-002",
    queueItemId: "queue-drafted-002",
    processingRunId: "run-fixture-001",
    status: "proposed",
    priority: "normal",
    recommendedAction: "review",
    extraction: {
      fieldValues: {
        direction: "purchase",
        documentType: "ticket",
        documentDate: "2026-06-18",
        quarter: "2026-Q2",
        counterpartyName: "Renfe",
        counterpartyId: null,
        baseAmount: "36.36",
        vatAmount: "3.64",
        totalAmount: "40.00",
        currency: "EUR",
        category: "Travel",
        notes: "Ticket appears business-related, but trip purpose is not present."
      },
      confidence: {
        overall: 0.82,
        fields: {
          totalAmount: 0.94,
          documentDate: 0.88,
          category: 0.55
        }
      },
      reviewReasons: ["unclear_tax_treatment"]
    },
    createdAt: "2026-07-01T08:27:00.000Z",
    updatedAt: "2026-07-01T08:27:00.000Z"
  }
};

let reviewedRecords: Record<string, AutonomoReviewedRecordSummary> = {
  "doc-reviewed-sale-003": {
    recordId: "record-reviewed-sale-003",
    documentId: "doc-reviewed-sale-003",
    counterpartyId: "cp-customer-senda-studio",
    direction: "sale",
    documentType: "invoice",
    recordDate: "2026-05-31",
    quarter: "2026-Q2",
    currency: "EUR",
    baseAmount: "1800.00",
    vatAmount: "378.00",
    totalAmount: "2178.00",
    category: "Client services",
    notes: "Reviewed fixture record.",
    createdAt: "2026-07-01T08:44:00.000Z",
    updatedAt: "2026-07-01T08:44:00.000Z"
  },
  "doc-reviewed-purchase-006": {
    recordId: "record-reviewed-purchase-006",
    documentId: "doc-reviewed-purchase-006",
    counterpartyId: "cp-supplier-gestoria-norte",
    direction: "purchase",
    documentType: "invoice",
    recordDate: "2026-06-01",
    quarter: "2026-Q2",
    currency: "EUR",
    baseAmount: "950.00",
    vatAmount: "199.50",
    totalAmount: "1149.50",
    category: "Office rent",
    notes: "Reviewed fixture purchase.",
    createdAt: "2026-07-01T08:48:00.000Z",
    updatedAt: "2026-07-01T08:48:00.000Z"
  }
};

const fixtureFiles = new Map<string, Blob>();

export const fixtureAutonomoApi = {
  async bootstrapWorkspace(): Promise<AutonomoWorkspaceBootstrapResponse> {
    return response({ workspace });
  },

  async updateBusinessProfile(payload: AutonomoWorkspaceBusinessProfileUpdateRequest): Promise<AutonomoWorkspaceBootstrapResponse> {
    const now = new Date().toISOString();
    workspace = {
      ...workspace,
      businessProfile: {
        profileStatus: "complete",
        kind: payload.kind,
        legalName: payload.legalName.trim(),
        tradeName: clean(payload.tradeName),
        taxId: clean(payload.taxId),
        vatId: clean(payload.vatId),
        country: payload.country.trim().toUpperCase(),
        fiscalAddress: clean(payload.fiscalAddress),
        updatedAt: now
      },
      updatedAt: now
    };
    return response({ workspace });
  },

  async listCounterparties(limit = 100): Promise<AutonomoCounterpartiesListResponse> {
    return response({ workspace, counterparties: counterparties.slice(0, limit) });
  },

  async createCounterparty(payload: AutonomoCounterpartyCreateRequest): Promise<AutonomoCounterpartyResponse> {
    const now = new Date().toISOString();
    const counterparty: AutonomoCounterpartySummary = {
      counterpartyId: `cp-fixture-${slug(payload.displayName)}-${Date.now()}`,
      workspaceId: workspace.workspaceId,
      kind: payload.kind,
      displayName: payload.displayName.trim(),
      taxId: clean(payload.taxId),
      vatId: clean(payload.vatId),
      country: clean(payload.country)?.toUpperCase() ?? null,
      notes: clean(payload.notes),
      createdAt: now,
      updatedAt: now
    };
    counterparties = [counterparty, ...counterparties];
    return response({ workspace, counterparty });
  },

  async listDocuments(filters: AutonomoDocumentListQuery = {}): Promise<AutonomoDocumentsListResponse> {
    const limit = clamp(filters.limit ?? 25, 1, 100);
    const filtered = documents
      .filter((document) => !filters.status || document.status === filters.status)
      .filter((document) => !filters.quarter || document.quarter === filters.quarter)
      .filter((document) => !filters.direction || document.direction === filters.direction)
      .filter((document) => !filters.documentType || document.documentType === filters.documentType)
      .filter((document) => !filters.intakeMode || document.intakeMode === filters.intakeMode)
      .filter((document) => !filters.counterpartyId || document.counterpartyId === filters.counterpartyId)
      .slice(0, limit);

    return response({ workspace, documents: filtered });
  },

  async listRecords(filters: AutonomoRecordListQuery = {}): Promise<AutonomoRecordsListResponse> {
    const limit = clamp(filters.limit ?? 100, 1, 250);
    const filtered = Object.values(reviewedRecords)
      .map(recordListItem)
      .filter((record) => !filters.dateFrom || record.recordDate >= filters.dateFrom)
      .filter((record) => !filters.dateTo || record.recordDate <= filters.dateTo)
      .filter((record) => !filters.quarter || record.quarter === filters.quarter)
      .filter((record) => !filters.direction || record.direction === filters.direction)
      .filter((record) => !filters.documentType || record.documentType === filters.documentType)
      .filter((record) => !filters.counterpartyId || record.counterpartyId === filters.counterpartyId)
      .filter((record) => !filters.category || record.category === filters.category)
      .sort((left, right) => right.recordDate.localeCompare(left.recordDate) || right.createdAt.localeCompare(left.createdAt))
      .slice(0, limit);

    return response({ workspace, records: filtered });
  },

  async getDocumentDetail(documentId: string): Promise<AutonomoDocumentDetailResponse> {
    const document = findDocument(documentId);
    return response({
      workspace,
      document,
      latestDraft: drafts[documentId] ?? null,
      reviewedRecord: reviewedRecords[documentId] ?? null
    });
  },

  async saveDocumentReview(documentId: string, payload: AutonomoDocumentManualReviewRequest): Promise<AutonomoDocumentDetailResponse> {
    const document = findDocument(documentId);
    const now = new Date().toISOString();
    const nextDocument: AutonomoDocumentListItem = {
      ...document,
      status: payload.status,
      direction: payload.direction,
      documentType: payload.documentType,
      title: payload.title,
      documentDate: payload.documentDate,
      quarter: payload.quarter,
      counterpartyId: payload.counterpartyId,
      queueStatus: payload.status === "queued" ? "queued" : "superseded",
      updatedAt: now
    };

    documents = documents.map((item) => (item.documentId === documentId ? nextDocument : item));

    if (payload.status === "reviewed" && payload.reviewedRecord) {
      const existing = reviewedRecords[documentId];
      reviewedRecords = {
        ...reviewedRecords,
        [documentId]: {
          recordId: existing?.recordId ?? `record-${documentId}`,
          documentId,
          ...payload.reviewedRecord,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now
        }
      };
    } else {
      const { [documentId]: _removed, ...rest } = reviewedRecords;
      reviewedRecords = rest;
    }

    return fixtureAutonomoApi.getDocumentDetail(documentId);
  },

  async uploadFile(file: File, intakeMode: AutonomoIntakeMode = "ai_intake"): Promise<AutonomoUploadCompletionResponse> {
    const now = new Date().toISOString();
    const documentId = `doc-web-upload-${Date.now()}`;
    const assetId = `asset-web-upload-${Date.now()}`;
    const queueItemId = intakeMode === "ai_intake" ? `queue-web-upload-${Date.now()}` : null;
    const contentType = normalizeContentType(file.type);
    const document: AutonomoDocumentListItem = {
      documentId,
      assetId,
      workspaceId: workspace.workspaceId,
      status: intakeMode === "ai_intake" ? "queued" : "needs_review",
      direction: "unknown",
      documentType: "unknown",
      title: file.name.replace(/\.[^.]+$/, ""),
      documentDate: null,
      quarter: currentQuarter(),
      counterpartyId: null,
      originalFilename: file.name,
      contentType,
      byteSize: file.size,
      source: "web_upload",
      intakeMode,
      uploadedByUserId: workspace.ownerUserId,
      queueItemId,
      queueStatus: intakeMode === "ai_intake" ? "queued" : null,
      createdAt: now,
      updatedAt: now
    };

    documents = [document, ...documents];
    fixtureFiles.set(documentId, file);

    return {
      appId: "autonomoav",
      workspaceId: workspace.workspaceId,
      documentId,
      assetId,
      uploadId: `upload-${documentId}`,
      queueItemId,
      status: intakeMode === "ai_intake" ? "queued" : "needs_review",
      documentStatus: intakeMode === "ai_intake" ? "queued" : "needs_review",
      intakeMode,
      storageKey: `fixture/autonomo/${documentId}/${file.name}`,
      bytesReceived: file.size,
      uploadedAt: now,
      generatedAt: now
    };
  },

  async getDocumentFile(documentId: string): Promise<{ blob: Blob; filename: string; contentType: string }> {
    const document = findDocument(documentId);
    const blob =
      fixtureFiles.get(documentId) ??
      new Blob([fixturePreviewText(document)], { type: document.contentType === "application/pdf" ? "text/plain" : document.contentType });
    return {
      blob,
      filename: document.originalFilename,
      contentType: blob.type || document.contentType
    };
  },

  async quarterSummary(quarter: string): Promise<AutonomoQuarterSummaryResponse> {
    const records = Object.values(reviewedRecords).filter((record) => record.quarter === quarter);
    const currencies = summarizeCurrencies(records);
    const byDocumentType = summarizeDocumentTypes(records);
    return response({
      workspace,
      quarter,
      reviewedDocumentCount: records.length,
      currencies,
      byDocumentType
    });
  }
};

function response<T extends object>(payload: T): T & { appId: "autonomoav"; generatedAt: string } {
  return {
    appId: "autonomoav",
    generatedAt: new Date().toISOString(),
    ...payload
  };
}

function findDocument(documentId: string) {
  const document = documents.find((item) => item.documentId === documentId);
  if (!document) {
    throw new Error(`Fixture document not found: ${documentId}`);
  }
  return document;
}

function recordListItem(record: AutonomoReviewedRecordSummary): AutonomoRecordListItem {
  const document = findDocument(record.documentId);
  const counterparty = record.counterpartyId
    ? counterparties.find((item) => item.counterpartyId === record.counterpartyId) ?? null
    : null;

  return {
    recordId: record.recordId,
    documentId: record.documentId,
    counterpartyId: record.counterpartyId,
    counterpartyDisplayName: counterparty?.displayName ?? null,
    counterpartyKind: counterparty?.kind ?? null,
    direction: record.direction,
    documentType: record.documentType,
    recordDate: record.recordDate,
    quarter: record.quarter,
    currency: record.currency,
    baseAmount: record.baseAmount,
    vatAmount: record.vatAmount,
    totalAmount: record.totalAmount,
    category: record.category,
    notes: record.notes,
    documentTitle: document.title,
    documentStatus: document.status,
    originalFilename: document.originalFilename,
    source: document.source,
    intakeMode: document.intakeMode,
    contentType: document.contentType,
    byteSize: document.byteSize,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt
  };
}

function summarizeCurrencies(records: AutonomoReviewedRecordSummary[]): AutonomoQuarterCurrencySummary[] {
  const byCurrency = new Map<string, AutonomoQuarterCurrencySummary>();
  for (const record of records) {
    const summary = byCurrency.get(record.currency) ?? emptyCurrencySummary(record.currency);
    const bucket = record.direction === "sale" ? summary.sale : record.direction === "purchase" ? summary.purchase : summary.unknown;
    addToBucket(bucket, record);
    summary.netTotalAmount = moneyString(Number(summary.sale.totalAmount) - Number(summary.purchase.totalAmount));
    byCurrency.set(record.currency, summary);
  }
  return [...byCurrency.values()];
}

function summarizeDocumentTypes(records: AutonomoReviewedRecordSummary[]): AutonomoQuarterDocumentTypeSummary[] {
  const byType = new Map<string, AutonomoQuarterDocumentTypeSummary>();
  for (const record of records) {
    const documentType = reviewedTypeFromDocumentType(record.documentType);
    const key = `${record.currency}:${record.direction}:${documentType}`;
    const summary =
      byType.get(key) ??
      {
        currency: record.currency,
        direction: record.direction,
        documentType,
        count: 0,
        baseAmount: "0.00",
        vatAmount: "0.00",
        totalAmount: "0.00"
      };
    summary.count += 1;
    summary.baseAmount = moneyString(Number(summary.baseAmount) + Number(record.baseAmount));
    summary.vatAmount = moneyString(Number(summary.vatAmount) + Number(record.vatAmount));
    summary.totalAmount = moneyString(Number(summary.totalAmount) + Number(record.totalAmount));
    byType.set(key, summary);
  }
  return [...byType.values()];
}

function emptyCurrencySummary(currency: string): AutonomoQuarterCurrencySummary {
  return {
    currency,
    sale: emptyBucket(),
    purchase: emptyBucket(),
    unknown: emptyBucket(),
    netTotalAmount: "0.00"
  };
}

function emptyBucket() {
  return {
    count: 0,
    baseAmount: "0.00",
    vatAmount: "0.00",
    totalAmount: "0.00"
  };
}

function addToBucket(bucket: ReturnType<typeof emptyBucket>, record: AutonomoReviewedRecordSummary) {
  bucket.count += 1;
  bucket.baseAmount = moneyString(Number(bucket.baseAmount) + Number(record.baseAmount));
  bucket.vatAmount = moneyString(Number(bucket.vatAmount) + Number(record.vatAmount));
  bucket.totalAmount = moneyString(Number(bucket.totalAmount) + Number(record.totalAmount));
}

function clean(value: string | null | undefined) {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : null;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

function slug(value: string) {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .toLowerCase();
}

function normalizeContentType(value: string) {
  if (value === "image/jpeg" || value === "image/png" || value === "image/webp" || value === "image/heic" || value === "image/heif") {
    return value;
  }
  return "application/pdf";
}

function fixturePreviewText(document: AutonomoDocumentListItem) {
  return [
    "Autonomo AV fixture preview",
    "",
    `Document: ${document.title ?? document.originalFilename}`,
    `Status: ${document.status}`,
    `Source: ${document.source}`,
    `Quarter: ${document.quarter ?? (quarterForDate(document.documentDate ?? "") || "not set")}`,
    "",
    "The real app downloads the original file through /v1/apps/autonomo/documents/:documentId/file."
  ].join("\n");
}
