export const autonomoUploadMaxByteSize = 25 * 1024 * 1024;

export const autonomoUploadContentTypeValues = [
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif"
] as const;

export type AutonomoUploadContentType = (typeof autonomoUploadContentTypeValues)[number];

export type AutonomoDocumentStatus =
  | "uploaded"
  | "queued"
  | "processing"
  | "drafted"
  | "needs_review"
  | "reviewed"
  | "duplicate"
  | "ignored"
  | "failed"
  | "quarantined";

export type AutonomoManualDocumentStatus =
  | "queued"
  | "needs_review"
  | "reviewed"
  | "duplicate"
  | "ignored"
  | "failed";

export type AutonomoDocumentDirection = "sale" | "purchase" | "unknown";
export type AutonomoDocumentType =
  | "invoice"
  | "ticket"
  | "receipt"
  | "tax_document"
  | "accountant_file"
  | "other"
  | "unknown";
export type AutonomoReviewedDocumentType = "invoice" | "ticket" | "receipt" | "other";
export type AutonomoCounterpartyKind = "supplier" | "customer" | "both" | "unknown";
export type AutonomoBusinessProfileKind = "self_employed" | "company" | "other";
export type AutonomoBusinessProfileStatus = "missing" | "complete";
export type AutonomoIntakeSource =
  | "ios_camera"
  | "ios_files"
  | "ios_share"
  | "macos_files"
  | "macos_drag_drop"
  | "macos_share"
  | "macos_service"
  | "web_upload";
export type AutonomoIntakeQueueItemStatus = "queued" | "claimed" | "processing" | "drafted" | "failed" | "superseded";
export type AutonomoPriority = "low" | "normal" | "interesting" | "urgent" | "blocking";
export type AutonomoRecommendedAction =
  | "review"
  | "pay_attention_to_due_date"
  | "create_follow_up"
  | "archive_only"
  | "ask_user"
  | "ignore_or_spam";

export type AutonomoAccessMode = "guest" | "signedInFree" | "signedInPro";
export type AutonomoPlanTier = "free" | "pro";

export interface AutonomoAccessCapabilities {
  isSignedIn: boolean;
  canUseBackend: boolean;
  canUsePremiumFeatures: boolean;
  canUseCloudSync: boolean;
  canManagePlan: boolean;
}

export interface AutonomoAppAccess {
  appId: "autonomoav" | string;
  accessMode: AutonomoAccessMode;
  planTier: AutonomoPlanTier;
  capabilities: AutonomoAccessCapabilities;
  limits: Record<string, unknown>;
}

export interface AutonomoMeAccessResponse {
  viewer: {
    isAuthenticated: boolean;
    userId: string | null;
    identityProvider: string | null;
  };
  apps: AutonomoAppAccess[];
  generatedAt: string;
}

export interface AutonomoWorkspaceSummary {
  workspaceId: string;
  ownerUserId: string;
  displayName: string;
  country: string;
  timezone: string;
  defaultCurrency: string;
  status: "active" | "archived" | "disabled";
  businessProfile: AutonomoWorkspaceBusinessProfile;
  createdAt: string;
  updatedAt: string;
}

export interface AutonomoWorkspaceBusinessProfile {
  profileStatus: AutonomoBusinessProfileStatus;
  kind: AutonomoBusinessProfileKind | null;
  legalName: string | null;
  tradeName: string | null;
  taxId: string | null;
  vatId: string | null;
  country: string | null;
  fiscalAddress: string | null;
  updatedAt: string | null;
}

export interface AutonomoWorkspaceBusinessProfileUpdateRequest {
  kind: AutonomoBusinessProfileKind;
  legalName: string;
  tradeName?: string | null;
  taxId?: string | null;
  vatId?: string | null;
  country: string;
  fiscalAddress?: string | null;
}

export interface AutonomoWorkspaceBootstrapResponse {
  appId: "autonomoav";
  workspace: AutonomoWorkspaceSummary;
  generatedAt: string;
}

export interface AutonomoCounterpartySummary {
  counterpartyId: string;
  workspaceId: string;
  kind: AutonomoCounterpartyKind;
  displayName: string;
  taxId: string | null;
  vatId: string | null;
  country: string | null;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AutonomoCounterpartyCreateRequest {
  kind: AutonomoCounterpartyKind;
  displayName: string;
  taxId?: string | null;
  vatId?: string | null;
  country?: string | null;
  notes?: string | null;
}

export interface AutonomoCounterpartiesListResponse {
  appId: "autonomoav";
  workspace: AutonomoWorkspaceSummary;
  counterparties: AutonomoCounterpartySummary[];
  generatedAt: string;
}

export interface AutonomoCounterpartyResponse {
  appId: "autonomoav";
  workspace: AutonomoWorkspaceSummary;
  counterparty: AutonomoCounterpartySummary;
  generatedAt: string;
}

export interface AutonomoDocumentListItem {
  documentId: string;
  assetId: string;
  workspaceId: string;
  status: AutonomoDocumentStatus;
  direction: AutonomoDocumentDirection;
  documentType: AutonomoDocumentType;
  title: string | null;
  documentDate: string | null;
  quarter: string | null;
  counterpartyId: string | null;
  originalFilename: string;
  contentType: AutonomoUploadContentType;
  byteSize: number;
  source: AutonomoIntakeSource;
  uploadedByUserId: string;
  queueItemId: string | null;
  queueStatus: AutonomoIntakeQueueItemStatus | null;
  createdAt: string;
  updatedAt: string;
}

export interface AutonomoDraftConfidence {
  overall: number;
  fields: Record<string, number>;
}

export interface AutonomoDraftFieldValues {
  direction: AutonomoDocumentDirection;
  documentType: AutonomoDocumentType;
  documentDate: string | null;
  quarter: string | null;
  counterpartyName: string | null;
  counterpartyId: string | null;
  baseAmount: string | null;
  vatAmount: string | null;
  totalAmount: string | null;
  currency: string | null;
  category: string | null;
  notes: string | null;
}

export interface AutonomoDraftExtraction {
  fieldValues: AutonomoDraftFieldValues;
  confidence: AutonomoDraftConfidence;
  reviewReasons: string[];
}

export interface AutonomoDocumentDraftSummary {
  draftId: string;
  documentId: string;
  queueItemId: string;
  processingRunId: string;
  status: "proposed" | "accepted" | "rejected" | "superseded";
  extraction: AutonomoDraftExtraction;
  priority?: AutonomoPriority;
  recommendedAction?: AutonomoRecommendedAction;
  createdAt: string;
  updatedAt: string;
}

export interface AutonomoReviewedRecordSummary {
  recordId: string;
  documentId: string;
  counterpartyId: string | null;
  direction: AutonomoDocumentDirection;
  documentType: AutonomoReviewedDocumentType;
  recordDate: string;
  quarter: string;
  currency: string;
  baseAmount: string;
  vatAmount: string;
  totalAmount: string;
  category: string | null;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AutonomoDocumentsListResponse {
  appId: "autonomoav";
  workspace: AutonomoWorkspaceSummary;
  documents: AutonomoDocumentListItem[];
  generatedAt: string;
}

export interface AutonomoDocumentDetailResponse {
  appId: "autonomoav";
  workspace: AutonomoWorkspaceSummary;
  document: AutonomoDocumentListItem;
  latestDraft: AutonomoDocumentDraftSummary | null;
  reviewedRecord: AutonomoReviewedRecordSummary | null;
  generatedAt: string;
}

export interface AutonomoDocumentListQuery {
  status?: AutonomoDocumentStatus;
  quarter?: string;
  source?: AutonomoIntakeSource;
  direction?: AutonomoDocumentDirection;
  documentType?: AutonomoDocumentType;
  counterpartyId?: string;
  limit?: number;
}

export interface AutonomoReviewedRecordUpdate {
  counterpartyId: string | null;
  direction: AutonomoDocumentDirection;
  documentType: AutonomoReviewedDocumentType;
  recordDate: string;
  quarter: string;
  currency: string;
  baseAmount: string;
  vatAmount: string;
  totalAmount: string;
  category: string | null;
  notes: string | null;
}

export interface AutonomoDocumentManualReviewRequest {
  status: AutonomoManualDocumentStatus;
  title: string | null;
  direction: AutonomoDocumentDirection;
  documentType: AutonomoDocumentType;
  documentDate: string | null;
  quarter: string | null;
  counterpartyId: string | null;
  reviewedRecord: AutonomoReviewedRecordUpdate | null;
}

export interface AutonomoQuarterTotalsBucket {
  count: number;
  baseAmount: string;
  vatAmount: string;
  totalAmount: string;
}

export interface AutonomoQuarterCurrencySummary {
  currency: string;
  sale: AutonomoQuarterTotalsBucket;
  purchase: AutonomoQuarterTotalsBucket;
  unknown: AutonomoQuarterTotalsBucket;
  netTotalAmount: string;
}

export interface AutonomoQuarterDocumentTypeSummary {
  currency: string;
  direction: AutonomoDocumentDirection;
  documentType: AutonomoReviewedDocumentType;
  count: number;
  baseAmount: string;
  vatAmount: string;
  totalAmount: string;
}

export interface AutonomoQuarterSummaryResponse {
  appId: "autonomoav";
  workspace: AutonomoWorkspaceSummary;
  quarter: string;
  reviewedDocumentCount: number;
  currencies: AutonomoQuarterCurrencySummary[];
  byDocumentType: AutonomoQuarterDocumentTypeSummary[];
  generatedAt: string;
}

export interface AutonomoPrepareUploadRequest {
  originalFilename: string;
  contentType: AutonomoUploadContentType;
  byteSize: number;
  sha256: string;
  source: "web_upload";
}

export interface AutonomoPreparedUploadResponse {
  appId: "autonomoav";
  workspaceId: string;
  documentId: string;
  assetId: string;
  uploadId: string;
  uploadUrl: string;
  completionUrl: string;
  method: "PUT";
  headers: Record<string, string>;
  expiresAt: string;
  generatedAt: string;
}

export interface AutonomoUploadCompletionResponse {
  appId: "autonomoav";
  workspaceId: string;
  documentId: string;
  assetId: string;
  uploadId: string;
  queueItemId: string;
  status: "queued";
  documentStatus: "queued";
  storageKey: string;
  bytesReceived: number;
  uploadedAt: string;
  generatedAt: string;
}

export interface AutonomoDocumentFileDownload {
  blob: Blob;
  filename: string;
  contentType: string;
}

export interface AutonomoEmailIntakeSettings {
  enabled: boolean;
  alias: string | null;
  status: "active" | "disabled" | "rotating";
}

export interface AutonomoUploadResult {
  response: AutonomoUploadCompletionResponse;
  file: File;
}
