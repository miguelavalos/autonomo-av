import type {
  AutonomoDocumentDetailResponse,
  AutonomoDocumentDirection,
  AutonomoDocumentDraftSummary,
  AutonomoDocumentListItem,
  AutonomoDocumentStatus,
  AutonomoDocumentType,
  AutonomoPriority,
  AutonomoReviewedDocumentType
} from "@/lib/autonomo-types";

export function labelFor(value: string | null | undefined) {
  if (!value) return "Not set";
  return value
    .split("_")
    .map((part) => `${part.slice(0, 1).toUpperCase()}${part.slice(1)}`)
    .join(" ");
}

export function currentQuarter(now = new Date()) {
  const quarter = Math.floor(now.getMonth() / 3) + 1;
  return `${now.getFullYear()}-Q${quarter}`;
}

export function quarterForDate(date: string) {
  const match = /^(\d{4})-(\d{2})-\d{2}$/.exec(date);
  if (!match) return "";
  const month = Number(match[2]);
  if (month < 1 || month > 12) return "";
  return `${match[1]}-Q${Math.floor((month - 1) / 3) + 1}`;
}

export function formatDate(value: string | null | undefined) {
  if (!value) return "Not set";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en", {
    dateStyle: "medium",
    timeStyle: value.includes("T") ? "short" : undefined
  }).format(date);
}

export function formatBytes(value: number) {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatMoney(value: string | number | null | undefined, currency = "EUR") {
  const amount = typeof value === "number" ? value : Number(value ?? 0);
  return new Intl.NumberFormat("en", {
    currency,
    style: "currency"
  }).format(Number.isFinite(amount) ? amount : 0);
}

export function moneyString(value: string | number | null | undefined) {
  const amount = Number(value ?? 0);
  return Number.isFinite(amount) ? amount.toFixed(2) : "0.00";
}

export function priorityForDocument(document: AutonomoDocumentListItem, detail?: AutonomoDocumentDetailResponse | null): AutonomoPriority {
  const draft = detail?.document.documentId === document.documentId ? detail.latestDraft : null;
  if (draft?.priority) return draft.priority;
  if (document.status === "failed" || document.status === "quarantined") return "blocking";
  if (document.status === "needs_review") return "urgent";
  if (document.status === "drafted") return "interesting";
  return "normal";
}

export function confidencePercent(draft: AutonomoDocumentDraftSummary | null | undefined) {
  if (!draft) return "No draft";
  return `${Math.round(draft.extraction.confidence.overall * 100)}%`;
}

export function statusTone(status: AutonomoDocumentStatus) {
  if (status === "failed" || status === "quarantined") return "danger";
  if (status === "needs_review") return "warning";
  if (status === "reviewed") return "success";
  if (status === "processing" || status === "queued" || status === "uploaded") return "info";
  return "muted";
}

export function priorityTone(priority: AutonomoPriority) {
  if (priority === "blocking" || priority === "urgent") return "danger";
  if (priority === "interesting") return "warning";
  if (priority === "low") return "muted";
  return "info";
}

export function directionLabel(direction: AutonomoDocumentDirection) {
  return direction === "sale" ? "Sale" : direction === "purchase" ? "Purchase" : "Unknown";
}

export function reviewedTypeFromDocumentType(documentType: AutonomoDocumentType): AutonomoReviewedDocumentType {
  return documentType === "invoice" || documentType === "ticket" || documentType === "receipt" ? documentType : "other";
}

export function filterText(value: string) {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function isValidMoney(value: string) {
  return /^(0|[1-9]\d*)(?:\.\d{1,2})?$/.test(value.trim());
}

export function optionalText(value: string) {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
