import { fixtureAutonomoApi } from "@/lib/autonomo-fixtures";
import type {
  AutonomoCounterpartiesListResponse,
  AutonomoCounterpartyCreateRequest,
  AutonomoCounterpartyResponse,
  AutonomoDocumentDetailResponse,
  AutonomoDocumentFileDownload,
  AutonomoDocumentListQuery,
  AutonomoDocumentManualReviewRequest,
  AutonomoDocumentsListResponse,
  AutonomoMeAccessResponse,
  AutonomoPrepareUploadRequest,
  AutonomoPreparedUploadResponse,
  AutonomoQuarterSummaryResponse,
  AutonomoUploadCompletionResponse,
  AutonomoUploadContentType,
  AutonomoWorkspaceBootstrapResponse,
  AutonomoWorkspaceBusinessProfileUpdateRequest
} from "@/lib/autonomo-types";
import {
  autonomoUploadContentTypeValues,
  autonomoUploadMaxByteSize
} from "@/lib/autonomo-types";

export type AutonomoTokenProvider = () => Promise<string | null>;

export class AutonomoApiClient {
  constructor(
    private readonly baseUrl: string,
    private readonly getToken: AutonomoTokenProvider,
    private readonly useFixtures: boolean
  ) {}

  fetchMeAccess(): Promise<AutonomoMeAccessResponse> {
    if (this.useFixtures) {
      return Promise.resolve(fixtureAutonomoAccessResponse());
    }
    return this.fetchJson("/v1/me/access?appId=autonomoav");
  }

  bootstrapWorkspace(): Promise<AutonomoWorkspaceBootstrapResponse> {
    if (this.useFixtures) return fixtureAutonomoApi.bootstrapWorkspace();
    return this.fetchJson("/v1/apps/autonomo/workspace/bootstrap", { method: "POST" });
  }

  updateBusinessProfile(payload: AutonomoWorkspaceBusinessProfileUpdateRequest): Promise<AutonomoWorkspaceBootstrapResponse> {
    if (this.useFixtures) return fixtureAutonomoApi.updateBusinessProfile(payload);
    return this.fetchJson("/v1/apps/autonomo/workspace/business-profile", {
      method: "PUT",
      body: payload
    });
  }

  listCounterparties(limit = 100): Promise<AutonomoCounterpartiesListResponse> {
    if (this.useFixtures) return fixtureAutonomoApi.listCounterparties(limit);
    return this.fetchJson(`/v1/apps/autonomo/counterparties?limit=${limit}`);
  }

  createCounterparty(payload: AutonomoCounterpartyCreateRequest): Promise<AutonomoCounterpartyResponse> {
    if (this.useFixtures) return fixtureAutonomoApi.createCounterparty(payload);
    return this.fetchJson("/v1/apps/autonomo/counterparties", {
      method: "POST",
      body: payload
    });
  }

  listDocuments(filters: AutonomoDocumentListQuery = {}): Promise<AutonomoDocumentsListResponse> {
    if (this.useFixtures) return fixtureAutonomoApi.listDocuments(filters);
    return this.fetchJson(`/v1/apps/autonomo/documents${queryString(filters)}`);
  }

  getDocumentDetail(documentId: string): Promise<AutonomoDocumentDetailResponse> {
    if (this.useFixtures) return fixtureAutonomoApi.getDocumentDetail(documentId);
    return this.fetchJson(`/v1/apps/autonomo/documents/${encodeURIComponent(documentId)}`);
  }

  saveDocumentReview(documentId: string, payload: AutonomoDocumentManualReviewRequest): Promise<AutonomoDocumentDetailResponse> {
    if (this.useFixtures) return fixtureAutonomoApi.saveDocumentReview(documentId, payload);
    return this.fetchJson(`/v1/apps/autonomo/documents/${encodeURIComponent(documentId)}`, {
      method: "PATCH",
      body: payload
    });
  }

  getDocumentFile(documentId: string, fallbackFilename: string): Promise<AutonomoDocumentFileDownload> {
    if (this.useFixtures) return fixtureAutonomoApi.getDocumentFile(documentId);
    return this.fetchBlob(`/v1/apps/autonomo/documents/${encodeURIComponent(documentId)}/file`, fallbackFilename);
  }

  quarterSummary(quarter: string): Promise<AutonomoQuarterSummaryResponse> {
    if (this.useFixtures) return fixtureAutonomoApi.quarterSummary(quarter);
    return this.fetchJson(`/v1/apps/autonomo/quarter-summary?quarter=${encodeURIComponent(quarter)}`);
  }

  async uploadFile(file: File): Promise<AutonomoUploadCompletionResponse> {
    const contentType = uploadContentTypeForFile(file);
    if (!contentType) {
      throw new AutonomoApiError(415, "unsupported_upload_type", "Autonomo AV supports PDF, JPEG, PNG, WebP, HEIC, and HEIF files.");
    }
    if (file.size > autonomoUploadMaxByteSize) {
      throw new AutonomoApiError(413, "upload_too_large", "Autonomo AV uploads are limited to 25 MB in V1.");
    }
    if (this.useFixtures) return fixtureAutonomoApi.uploadFile(file);

    const prepared = await this.prepareUpload({
      originalFilename: file.name,
      contentType,
      byteSize: file.size,
      sha256: await sha256Hex(file),
      source: "web_upload"
    });

    return this.putPreparedUpload(prepared, file, contentType);
  }

  private prepareUpload(payload: AutonomoPrepareUploadRequest): Promise<AutonomoPreparedUploadResponse> {
    return this.fetchJson("/v1/apps/autonomo/uploads/prepare", {
      method: "POST",
      body: payload
    });
  }

  private async putPreparedUpload(
    prepared: AutonomoPreparedUploadResponse,
    file: File,
    contentType: AutonomoUploadContentType
  ): Promise<AutonomoUploadCompletionResponse> {
    const baseUrl = this.requiredBaseUrl();
    const uploadUrl = browserUploadUrl(baseUrl, prepared);
    const headers = preparedUploadHeaders(prepared.headers, contentType, uploadUrl, baseUrl);
    if (shouldAuthorizePreparedUpload(uploadUrl, baseUrl)) {
      headers.set("Authorization", `Bearer ${await this.requiredToken()}`);
      headers.set("x-appsav-app-id", "autonomoav");
      headers.set("x-appsav-platform", "web");
    }

    const response = await fetch(uploadUrl, {
      method: prepared.method,
      headers,
      body: file
    });

    if (!response.ok) {
      throw await apiError(response, "Autonomo AV upload failed.");
    }

    const text = await response.text();
    if (text.trim().length > 0) {
      return JSON.parse(text) as AutonomoUploadCompletionResponse;
    }

    return this.fetchJson(`/v1/apps/autonomo/uploads/${encodeURIComponent(prepared.uploadId)}/complete`, {
      method: "POST"
    });
  }

  private async fetchJson<T>(path: string, options: RequestOptions = {}): Promise<T> {
    const token = await this.requiredToken();
    const response = await fetch(`${this.requiredBaseUrl()}${path}`, {
      method: options.method ?? "GET",
      cache: "no-store",
      headers: {
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        "x-appsav-app-id": "autonomoav",
        "x-appsav-platform": "web",
        Authorization: `Bearer ${token}`
      },
      body: options.body ? JSON.stringify(options.body) : undefined
    });

    if (!response.ok) {
      throw await apiError(response, "Autonomo AV request failed.");
    }

    return response.json() as Promise<T>;
  }

  private async fetchBlob(path: string, fallbackFilename: string): Promise<AutonomoDocumentFileDownload> {
    const token = await this.requiredToken();
    const response = await fetch(`${this.requiredBaseUrl()}${path}`, {
      cache: "no-store",
      headers: {
        "x-appsav-app-id": "autonomoav",
        "x-appsav-platform": "web",
        Authorization: `Bearer ${token}`
      }
    });

    if (!response.ok) {
      throw await apiError(response, "Autonomo AV file request failed.");
    }

    return {
      blob: await response.blob(),
      filename: filenameFromDisposition(response.headers.get("content-disposition")) ?? fallbackFilename,
      contentType: response.headers.get("content-type") ?? "application/octet-stream"
    };
  }

  private requiredBaseUrl() {
    if (!this.baseUrl) {
      throw new AutonomoApiError(0, "missing_api_base_url", "Set VITE_AUTONOMOAV_API_BASE_URL or enable fixture mode.");
    }
    return this.baseUrl;
  }

  private async requiredToken() {
    const token = await this.getToken();
    if (!token) {
      throw new AutonomoApiError(401, "missing_session_token", "A signed-in Account AV session token is required for live backend mode.");
    }
    return token;
  }
}

function fixtureAutonomoAccessResponse(): AutonomoMeAccessResponse {
  return {
    viewer: {
      isAuthenticated: true,
      userId: "fixture-user",
      identityProvider: "fixture"
    },
    apps: [
      {
        appId: "autonomoav",
        accessMode: "signedInPro",
        planTier: "pro",
        capabilities: {
          isSignedIn: true,
          canUseBackend: true,
          canUsePremiumFeatures: true,
          canUseCloudSync: true,
          canManagePlan: true
        },
        limits: {}
      }
    ],
    generatedAt: new Date().toISOString()
  };
}

export class AutonomoApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string
  ) {
    super(message);
  }
}

type RequestOptions = {
  method?: "GET" | "PATCH" | "POST" | "PUT";
  body?: unknown;
};

function queryString(filters: AutonomoDocumentListQuery) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(filters)) {
    if (value !== undefined && value !== null && String(value).trim() !== "") {
      params.set(key, String(value));
    }
  }
  const serialized = params.toString();
  return serialized ? `?${serialized}` : "";
}

function uploadContentTypeForFile(file: File): AutonomoUploadContentType | null {
  const normalized = file.type.split(";", 1)[0]?.trim().toLowerCase();
  if (autonomoUploadContentTypeValues.includes(normalized as AutonomoUploadContentType)) {
    return normalized as AutonomoUploadContentType;
  }
  if (/\.pdf$/i.test(file.name)) return "application/pdf";
  if (/\.jpe?g$/i.test(file.name)) return "image/jpeg";
  if (/\.png$/i.test(file.name)) return "image/png";
  if (/\.webp$/i.test(file.name)) return "image/webp";
  if (/\.hei[cf]$/i.test(file.name)) return file.name.toLowerCase().endsWith("heic") ? "image/heic" : "image/heif";
  return null;
}

async function sha256Hex(file: File) {
  const digest = await crypto.subtle.digest("SHA-256", await file.arrayBuffer());
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function apiError(response: Response, fallbackMessage: string) {
  const payload = await response.json().catch(() => null) as { error?: { code?: string; message?: string } } | null;
  return new AutonomoApiError(
    response.status,
    payload?.error?.code ?? "request_failed",
    payload?.error?.message ?? fallbackMessage
  );
}

function absoluteUrl(baseUrl: string, value: string) {
  if (/^https?:\/\//i.test(value)) return value;
  return `${baseUrl.replace(/\/$/, "")}${value.startsWith("/") ? value : `/${value}`}`;
}

function browserUploadUrl(baseUrl: string, prepared: AutonomoPreparedUploadResponse) {
  const apiUploadUrl = absoluteUrl(baseUrl, `/v1/apps/autonomo/uploads/${encodeURIComponent(prepared.uploadId)}`);
  const preparedUrl = absoluteUrl(baseUrl, prepared.uploadUrl || apiUploadUrl);
  return shouldAuthorizePreparedUpload(preparedUrl, baseUrl) ? preparedUrl : apiUploadUrl;
}

function preparedUploadHeaders(
  preparedHeaders: Record<string, string>,
  fallbackContentType: string,
  uploadUrl: string,
  baseUrl: string
) {
  const headers = new Headers(shouldAuthorizePreparedUpload(uploadUrl, baseUrl) ? {} : preparedHeaders);
  if (!headers.has("Content-Type")) {
    headers.set("Content-Type", fallbackContentType);
  }
  return headers;
}

function shouldAuthorizePreparedUpload(uploadUrl: string, baseUrl: string) {
  try {
    return new URL(uploadUrl).origin === new URL(baseUrl).origin;
  } catch {
    return false;
  }
}

function filenameFromDisposition(header: string | null) {
  if (!header) return null;
  const encoded = /filename\*=UTF-8''([^;]+)/i.exec(header)?.[1];
  if (encoded) {
    try {
      return decodeURIComponent(encoded);
    } catch {
      return encoded;
    }
  }
  return /filename="?([^";]+)"?/i.exec(header)?.[1] ?? null;
}
