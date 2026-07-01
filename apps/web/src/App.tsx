import { AppShell, AppsAvWebProvider, AuthSkeleton, getAppsAvLocaleFromSearch } from "@avalsys/apps-av-web";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  AlertTriangle,
  ArrowDownToLine,
  CheckCircle2,
  Copy,
  FileText,
  Filter,
  Inbox,
  Loader2,
  LogIn,
  Plus,
  RefreshCw,
  RotateCcw,
  Search,
  Settings,
  UploadCloud,
  X
} from "lucide-react";
import { useEffect, useMemo, useRef, useState, type DragEvent, type ReactNode } from "react";
import { toast } from "sonner";
import { AutonomoApiClient } from "@/lib/autonomo-api-client";
import {
  AutonomoAccountSignIn,
  AutonomoAuthProvider,
  useAutonomoAuthSession,
  type AutonomoAuthSession
} from "@/lib/autonomo-auth";
import {
  autonomoAccent,
  autonomoFooterLabels,
  autonomoNavLinks,
  autonomoProductConfig,
  autonomoShellLabels,
  getAutonomoApiBaseUrl,
  getEmailIntakeSettings,
  useAutonomoFixtures
} from "@/lib/autonomo-config";
import {
  confidencePercent,
  currentQuarter,
  directionLabel,
  filterText,
  formatBytes,
  formatDate,
  formatMoney,
  isValidMoney,
  labelFor,
  optionalText,
  priorityForDocument,
  priorityTone,
  quarterForDate,
  reviewedTypeFromDocumentType,
  statusTone
} from "@/lib/autonomo-display";
import {
  autonomoUploadContentTypeValues,
  type AutonomoCounterpartyKind,
  type AutonomoCounterpartySummary,
  type AutonomoDocumentDetailResponse,
  type AutonomoDocumentDirection,
  type AutonomoDocumentListItem,
  type AutonomoDocumentStatus,
  type AutonomoDocumentType,
  type AutonomoEmailIntakeSettings,
  type AutonomoManualDocumentStatus,
  type AutonomoPriority,
  type AutonomoQuarterSummaryResponse,
  type AutonomoReviewedDocumentType
} from "@/lib/autonomo-types";

const statuses: Array<AutonomoDocumentStatus | "all"> = [
  "all",
  "queued",
  "processing",
  "drafted",
  "needs_review",
  "reviewed",
  "duplicate",
  "ignored",
  "failed",
  "quarantined"
];
const directions: Array<AutonomoDocumentDirection | "all"> = ["all", "sale", "purchase", "unknown"];
const documentTypes: Array<AutonomoDocumentType | "all"> = ["all", "invoice", "ticket", "receipt", "tax_document", "accountant_file", "other", "unknown"];
const sources = ["all", "web_upload", "ios_camera", "ios_files", "ios_share", "email_attachment", "email_body"] as const;
const priorities: Array<AutonomoPriority | "all"> = ["all", "low", "normal", "interesting", "urgent", "blocking"];
const manualStatuses: AutonomoManualDocumentStatus[] = ["queued", "needs_review", "reviewed", "duplicate", "ignored", "failed"];
const reviewedDocumentTypes: AutonomoReviewedDocumentType[] = ["invoice", "ticket", "receipt", "other"];
const counterpartyKinds: AutonomoCounterpartyKind[] = ["supplier", "customer", "both", "unknown"];
const uploadAccept = `${autonomoUploadContentTypeValues.join(",")},.pdf,.jpg,.jpeg,.png,.webp,.heic,.heif`;

type AppRoute = "inbox" | "quarter" | "settings" | "sign-in";

type FiltersState = {
  status: AutonomoDocumentStatus | "all";
  quarter: string;
  source: (typeof sources)[number];
  direction: AutonomoDocumentDirection | "all";
  documentType: AutonomoDocumentType | "all";
  counterpartyId: string;
  priority: AutonomoPriority | "all";
  limit: number;
};

type ReviewFormState = {
  title: string;
  status: AutonomoManualDocumentStatus;
  direction: AutonomoDocumentDirection;
  documentType: AutonomoReviewedDocumentType;
  documentDate: string;
  quarter: string;
  counterpartyId: string;
  currency: string;
  baseAmount: string;
  vatAmount: string;
  totalAmount: string;
  category: string;
  notes: string;
};

type CounterpartyFormState = {
  kind: AutonomoCounterpartyKind;
  displayName: string;
  taxId: string;
  vatId: string;
  country: string;
  notes: string;
};

type PreviewFileState = {
  url: string;
  filename: string;
  contentType: string;
};

const emptyCounterpartyForm: CounterpartyFormState = {
  kind: "supplier",
  displayName: "",
  taxId: "",
  vatId: "",
  country: "ES",
  notes: ""
};

const emptyReviewForm: ReviewFormState = {
  title: "",
  status: "needs_review",
  direction: "unknown",
  documentType: "invoice",
  documentDate: "",
  quarter: currentQuarter(),
  counterpartyId: "",
  currency: "EUR",
  baseAmount: "0.00",
  vatAmount: "0.00",
  totalAmount: "0.00",
  category: "",
  notes: ""
};

export function App() {
  const initialLocale = getAppsAvLocaleFromSearch(window.location.search);

  return (
    <AppsAvWebProvider initialLocale={initialLocale}>
      <AutonomoRuntime />
    </AppsAvWebProvider>
  );
}

function AutonomoRuntime() {
  const route = usePathRoute();
  const useFixtures = useAutonomoFixtures();

  return (
    <AutonomoAuthProvider useFixtures={useFixtures}>
      <AutonomoAuthenticatedRuntime route={route} useFixtures={useFixtures} />
    </AutonomoAuthProvider>
  );
}

function AutonomoAuthenticatedRuntime({ route, useFixtures }: { route: AppRoute; useFixtures: boolean }) {
  const authSession = useAutonomoAuthSession();
  const emailIntake = useMemo(() => getEmailIntakeSettings(useFixtures), [useFixtures]);
  const client = useMemo(
    () =>
      new AutonomoApiClient(
        getAutonomoApiBaseUrl(),
        authSession.getToken,
        useFixtures
      ),
    [authSession.getToken, useFixtures]
  );
  const appRoute = route === "sign-in" ? "inbox" : route;

  if (!authSession.isLoaded) {
    return <AuthSkeleton />;
  }

  if (!useFixtures && authSession.authMode === "missing-config") {
    return <AuthConfigurationMissing />;
  }

  if (!useFixtures && (!authSession.isSignedIn || route === "sign-in")) {
    return <AutonomoSignInScreen authSession={authSession} route={route} />;
  }

  return (
    <AppShell
      currentPath={pathForRoute(appRoute)}
      footerLabels={autonomoFooterLabels}
      labels={autonomoShellLabels}
      navLinks={autonomoNavLinks}
      product={autonomoProductConfig}
    >
      <AutonomoSurface authSession={authSession} client={client} emailIntake={emailIntake} route={appRoute} useFixtures={useFixtures} />
    </AppShell>
  );
}

function AutonomoSurface({
  authSession,
  client,
  emailIntake,
  route,
  useFixtures
}: {
  authSession: AutonomoAuthSession;
  client: AutonomoApiClient;
  emailIntake: AutonomoEmailIntakeSettings;
  route: Exclude<AppRoute, "sign-in">;
  useFixtures: boolean;
}) {
  const queryClient = useQueryClient();
  const [filters, setFilters] = useState<FiltersState>({
    status: "all",
    quarter: "",
    source: "all",
    direction: "all",
    documentType: "all",
    counterpartyId: "all",
    priority: "all",
    limit: 25
  });
  const [quarter, setQuarter] = useState(currentQuarter());
  const [selectedDocumentId, setSelectedDocumentId] = useState<string | null>(null);

  const workspaceQuery = useQuery({
    queryFn: () => client.bootstrapWorkspace(),
    queryKey: ["autonomo-av", "workspace"]
  });
  const counterpartiesQuery = useQuery({
    enabled: workspaceQuery.isSuccess,
    queryFn: () => client.listCounterparties(100),
    queryKey: ["autonomo-av", "counterparties"]
  });
  const documentsQuery = useQuery({
    enabled: workspaceQuery.isSuccess,
    queryFn: () =>
      client.listDocuments({
        status: filters.status === "all" ? undefined : filters.status,
        quarter: filterText(filters.quarter),
        direction: filters.direction === "all" ? undefined : filters.direction,
        documentType: filters.documentType === "all" ? undefined : filters.documentType,
        counterpartyId: filters.counterpartyId === "all" ? undefined : filters.counterpartyId,
        limit: filters.limit
      }),
    queryKey: [
      "autonomo-av",
      "documents",
      filters.status,
      filters.quarter,
      filters.direction,
      filters.documentType,
      filters.counterpartyId,
      filters.limit
    ]
  });
  const overviewDocumentsQuery = useQuery({
    enabled: workspaceQuery.isSuccess,
    queryFn: () => client.listDocuments({ limit: 100 }),
    queryKey: ["autonomo-av", "documents", "overview"]
  });
  const quarterSummaryQuery = useQuery({
    enabled: workspaceQuery.isSuccess,
    queryFn: () => client.quarterSummary(quarter),
    queryKey: ["autonomo-av", "quarter-summary", quarter]
  });

  const documents = documentsQuery.data?.documents ?? [];
  const counterparties = counterpartiesQuery.data?.counterparties ?? [];
  const visibleDocuments = useMemo(
    () =>
      documents.filter((document) => {
        const sourceMatches = filters.source === "all" || document.source === filters.source;
        const priority = priorityForDocument(document);
        const priorityMatches = filters.priority === "all" || priority === filters.priority;
        return sourceMatches && priorityMatches;
      }),
    [documents, filters.priority, filters.source]
  );

  useEffect(() => {
    if (selectedDocumentId || visibleDocuments.length === 0) return;
    const firstActionable = visibleDocuments.find((document) => document.status === "needs_review" || document.status === "drafted" || document.status === "failed");
    setSelectedDocumentId((firstActionable ?? visibleDocuments[0])?.documentId ?? null);
  }, [selectedDocumentId, visibleDocuments]);

  const refreshAll = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["autonomo-av", "workspace"] }),
      queryClient.invalidateQueries({ queryKey: ["autonomo-av", "documents"] }),
      queryClient.invalidateQueries({ queryKey: ["autonomo-av", "counterparties"] }),
      queryClient.invalidateQueries({ queryKey: ["autonomo-av", "quarter-summary"] })
    ]);
  };

  const error =
    workspaceQuery.error?.message ??
    documentsQuery.error?.message ??
    overviewDocumentsQuery.error?.message ??
    counterpartiesQuery.error?.message ??
    quarterSummaryQuery.error?.message;

  return (
    <section className="autonomo-surface">
      <HeaderStrip authSession={authSession} useFixtures={useFixtures} onRefresh={() => void refreshAll()} isRefreshing={documentsQuery.isFetching || quarterSummaryQuery.isFetching} />
      {error ? <InlineAlert tone="danger" title="Autonomo AV could not load this workspace">{error}</InlineAlert> : null}

      {route === "inbox" ? (
        <InboxScreen
          client={client}
          counterparties={counterparties}
          documents={visibleDocuments}
          filters={filters}
          isLoading={documentsQuery.isFetching || counterpartiesQuery.isFetching}
          onFiltersChange={setFilters}
          onRefresh={refreshAll}
          selectedDocumentId={selectedDocumentId}
          setSelectedDocumentId={setSelectedDocumentId}
        />
      ) : null}

      {route === "quarter" ? (
        <QuarterScreen
          documents={overviewDocumentsQuery.data?.documents ?? []}
          isLoading={quarterSummaryQuery.isFetching || overviewDocumentsQuery.isFetching}
          quarter={quarter}
          setQuarter={setQuarter}
          summary={quarterSummaryQuery.data ?? null}
        />
      ) : null}

      {route === "settings" ? (
        <SettingsScreen
          emailIntake={emailIntake}
          workspace={workspaceQuery.data?.workspace ?? null}
        />
      ) : null}
    </section>
  );
}

function HeaderStrip({
  authSession,
  isRefreshing,
  onRefresh,
  useFixtures
}: {
  authSession: AutonomoAuthSession;
  isRefreshing: boolean;
  onRefresh: () => void;
  useFixtures: boolean;
}) {
  return (
    <div className="autonomo-header-strip">
      <div className="min-w-0">
        <div className="flex items-center gap-2 text-sm font-medium text-muted-foreground">
          <Inbox className="size-4" aria-hidden="true" />
          Signed-in workspace
        </div>
        <h1 className="mt-2 text-3xl font-semibold leading-tight text-foreground">Inbox review</h1>
        <p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">
          Upload business documents, review AI drafts, and keep reviewed quarter totals separate from pending work.
        </p>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <Badge tone={useFixtures ? "warning" : "success"}>{useFixtures ? "Fixture" : "Live"}</Badge>
        <Badge tone={authBadgeTone(authSession)}>{authSession.statusLabel}</Badge>
        <button className="icon-button" type="button" onClick={onRefresh} aria-label="Refresh Autonomo AV">
          {isRefreshing ? <Loader2 className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
        </button>
      </div>
    </div>
  );
}

function AuthConfigurationMissing() {
  return (
    <main className="autonomo-auth-page">
      <section className="auth-panel" aria-labelledby="auth-config-title">
        <Badge tone="danger">Live auth missing</Badge>
        <h1 id="auth-config-title">Autonomo AV needs Account AV auth configuration</h1>
        <p>
          Set Account AV auth env vars for live mode, or turn fixture mode back on for local product work.
        </p>
        <dl className="auth-config-list">
          <div><dt>Required for Account AV auth</dt><dd>VITE_ACCOUNTAV_PUBLISHABLE_KEY and VITE_ACCOUNTAV_API_BASE_URL</dd></div>
          <div><dt>Required for live backend</dt><dd>VITE_AUTONOMOAV_API_BASE_URL and VITE_AUTONOMOAV_USE_FIXTURES=false</dd></div>
          <div><dt>Temporary local fallback</dt><dd>VITE_AUTONOMOAV_DEV_BEARER_TOKEN</dd></div>
        </dl>
      </section>
    </main>
  );
}

function AutonomoSignInScreen({ authSession, route }: { authSession: AutonomoAuthSession; route: AppRoute }) {
  const fallbackRedirectUrl = safeReturnTo(window.location.search) ?? "/";
  const shouldRedirect = authSession.authMode === "account-av" && !authSession.isSignedIn && route !== "sign-in";

  useEffect(() => {
    if (shouldRedirect) {
      window.location.replace(`/sign-in?returnTo=${encodeURIComponent(currentReturnPath())}`);
    }
  }, [shouldRedirect]);

  if (shouldRedirect) {
    return <AuthSkeleton />;
  }

  return (
    <main className="autonomo-auth-page">
      <section className="auth-panel" aria-labelledby="auth-title">
        <div className="auth-mark" aria-hidden="true">
          <LogIn className="size-5" />
        </div>
        <Badge tone={authBadgeTone(authSession)}>{authSession.statusLabel}</Badge>
        <h1 id="auth-title">{authSession.isSignedIn ? "Autonomo AV is ready" : "Sign in to Autonomo AV"}</h1>
        <p>
          {authSession.isSignedIn
            ? "Open the inbox to continue reviewing workspace documents."
            : "Use your Account AV session to open the live inbox and backend workspace."}
        </p>
        {authSession.isSignedIn ? (
          <a className="primary-button auth-action" href={fallbackRedirectUrl}>
            Open inbox
          </a>
        ) : (
          <AutonomoAccountSignIn fallbackRedirectUrl={fallbackRedirectUrl} />
        )}
      </section>
    </main>
  );
}

function InboxScreen({
  client,
  counterparties,
  documents,
  filters,
  isLoading,
  onFiltersChange,
  onRefresh,
  selectedDocumentId,
  setSelectedDocumentId
}: {
  client: AutonomoApiClient;
  counterparties: AutonomoCounterpartySummary[];
  documents: AutonomoDocumentListItem[];
  filters: FiltersState;
  isLoading: boolean;
  onFiltersChange: (filters: FiltersState) => void;
  onRefresh: () => Promise<void>;
  selectedDocumentId: string | null;
  setSelectedDocumentId: (documentId: string | null) => void;
}) {
  const metrics = useMemo(() => metricsFromDocuments(documents), [documents]);

  return (
    <div className="grid gap-4">
      <div className="metric-row">
        <Metric label="Needs review" value={metrics.needsReview} tone="warning" />
        <Metric label="Drafted" value={metrics.drafted} tone="info" />
        <Metric label="Queued" value={metrics.queued} tone="muted" />
        <Metric label="Failed" value={metrics.failed} tone="danger" />
      </div>

      <div className="inbox-layout">
        <div className="grid min-w-0 gap-4">
          <UploadPanel client={client} onUploaded={onRefresh} />
          <FiltersPanel counterparties={counterparties} filters={filters} onChange={onFiltersChange} />
          <DocumentList
            documents={documents}
            isLoading={isLoading}
            selectedDocumentId={selectedDocumentId}
            onSelect={setSelectedDocumentId}
          />
        </div>
        <ReviewColumn
          client={client}
          counterparties={counterparties}
          selectedDocumentId={selectedDocumentId}
          onClose={() => setSelectedDocumentId(null)}
          onSaved={onRefresh}
        />
      </div>
    </div>
  );
}

function UploadPanel({ client, onUploaded }: { client: AutonomoApiClient; onUploaded: () => Promise<void> }) {
  const [dragActive, setDragActive] = useState(false);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const uploadMutation = useMutation({
    mutationFn: (file: File) => client.uploadFile(file),
    onSuccess: async (response) => {
      toast.success("Document queued", {
        description: `${response.documentId} is ready for Autonomo AV processing.`
      });
      setSelectedFile(null);
      if (inputRef.current) inputRef.current.value = "";
      await onUploaded();
    },
    onError: (error) => toast.error("Upload failed", { description: error.message })
  });

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setDragActive(false);
    const file = event.dataTransfer.files[0];
    if (file) {
      setSelectedFile(file);
      uploadMutation.mutate(file);
    }
  };

  return (
    <section className="panel upload-panel" aria-labelledby="upload-title">
      <div>
        <h2 id="upload-title" className="section-title">Add to inbox</h2>
        <p className="section-copy">Drop one PDF or image here, or choose a file. New items appear in the inbox as queued work.</p>
      </div>
      <div
        className={dragActive ? "drop-zone drop-zone-active" : "drop-zone"}
        onDragEnter={(event) => {
          event.preventDefault();
          setDragActive(true);
        }}
        onDragLeave={() => setDragActive(false)}
        onDragOver={(event) => event.preventDefault()}
        onDrop={onDrop}
      >
        <UploadCloud className="size-7 text-[var(--autonomo-accent)]" aria-hidden="true" />
        <div className="min-w-0">
          <div className="text-sm font-semibold">Drag and drop a document</div>
          <div className="text-xs text-muted-foreground">PDF, JPEG, PNG, WebP, HEIC, or HEIF up to 25 MB.</div>
        </div>
        <input
          ref={inputRef}
          className="sr-only"
          type="file"
          accept={uploadAccept}
          onChange={(event) => setSelectedFile(event.target.files?.[0] ?? null)}
        />
        <button className="secondary-button" type="button" onClick={() => inputRef.current?.click()}>
          <FileText className="size-4" aria-hidden="true" />
          Choose file
        </button>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {selectedFile ? (
          <span className="text-sm text-muted-foreground">
            {selectedFile.name} · {formatBytes(selectedFile.size)}
          </span>
        ) : (
          <span className="text-sm text-muted-foreground">No file selected.</span>
        )}
        <button
          className="primary-button"
          type="button"
          disabled={!selectedFile || uploadMutation.isPending}
          onClick={() => selectedFile ? uploadMutation.mutate(selectedFile) : undefined}
        >
          {uploadMutation.isPending ? <Loader2 className="size-4 animate-spin" /> : <UploadCloud className="size-4" />}
          Upload
        </button>
      </div>
    </section>
  );
}

function FiltersPanel({
  counterparties,
  filters,
  onChange
}: {
  counterparties: AutonomoCounterpartySummary[];
  filters: FiltersState;
  onChange: (filters: FiltersState) => void;
}) {
  const update = <K extends keyof FiltersState>(key: K, value: FiltersState[K]) => onChange({ ...filters, [key]: value });

  return (
    <section className="panel" aria-labelledby="filters-title">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h2 id="filters-title" className="section-title">Document filters</h2>
          <p className="section-copy">Narrow the inbox by status, quarter, source, direction, type, counterparty, or priority.</p>
        </div>
        <Filter className="size-5 text-muted-foreground" aria-hidden="true" />
      </div>
      <div className="filters-grid">
        <SelectField label="Status" value={filters.status} onChange={(value) => update("status", value as FiltersState["status"])}>
          {statuses.map((item) => <option key={item} value={item}>{item === "all" ? "All statuses" : labelFor(item)}</option>)}
        </SelectField>
        <InputField label="Quarter" value={filters.quarter} placeholder="2026-Q2" onChange={(value) => update("quarter", value)} />
        <SelectField label="Source" value={filters.source} onChange={(value) => update("source", value as FiltersState["source"])}>
          {sources.map((item) => <option key={item} value={item}>{item === "all" ? "All sources" : labelFor(item)}</option>)}
        </SelectField>
        <SelectField label="Direction" value={filters.direction} onChange={(value) => update("direction", value as FiltersState["direction"])}>
          {directions.map((item) => <option key={item} value={item}>{item === "all" ? "All directions" : labelFor(item)}</option>)}
        </SelectField>
        <SelectField label="Type" value={filters.documentType} onChange={(value) => update("documentType", value as FiltersState["documentType"])}>
          {documentTypes.map((item) => <option key={item} value={item}>{item === "all" ? "All types" : labelFor(item)}</option>)}
        </SelectField>
        <SelectField label="Counterparty" value={filters.counterpartyId} onChange={(value) => update("counterpartyId", value)}>
          <option value="all">All counterparties</option>
          {counterparties.map((counterparty) => <option key={counterparty.counterpartyId} value={counterparty.counterpartyId}>{counterparty.displayName}</option>)}
        </SelectField>
        <SelectField label="Priority" value={filters.priority} onChange={(value) => update("priority", value as FiltersState["priority"])}>
          {priorities.map((item) => <option key={item} value={item}>{item === "all" ? "All priorities" : labelFor(item)}</option>)}
        </SelectField>
        <InputField label="Limit" type="number" value={String(filters.limit)} onChange={(value) => update("limit", clampLimit(value))} />
      </div>
    </section>
  );
}

function DocumentList({
  documents,
  isLoading,
  onSelect,
  selectedDocumentId
}: {
  documents: AutonomoDocumentListItem[];
  isLoading: boolean;
  onSelect: (documentId: string) => void;
  selectedDocumentId: string | null;
}) {
  return (
    <section className="panel document-list-panel" aria-labelledby="document-list-title">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 id="document-list-title" className="section-title">Inbox</h2>
          <p className="section-copy">Open a row to review the draft and accepted record.</p>
        </div>
        {isLoading ? <Badge tone="muted">Loading</Badge> : <Badge tone="info">{documents.length} shown</Badge>}
      </div>
      <div className="document-table-wrap">
        <table className="document-table">
          <thead>
            <tr>
              <th>Document</th>
              <th>Status</th>
              <th>Source</th>
              <th>Direction</th>
              <th>Quarter</th>
              <th>Priority</th>
              <th>Size</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {documents.length === 0 ? (
              <tr>
                <td colSpan={8}>
                  <div className="empty-table">
                    <Search className="size-5" aria-hidden="true" />
                    No documents match the current filters.
                  </div>
                </td>
              </tr>
            ) : (
              documents.map((document) => {
                const priority = priorityForDocument(document);
                return (
                  <tr key={document.documentId} className={selectedDocumentId === document.documentId ? "selected-row" : undefined}>
                    <td>
                      <div className="cell-title">{document.title ?? document.originalFilename}</div>
                      <div className="cell-subtitle">{document.originalFilename}</div>
                    </td>
                    <td><Badge tone={statusTone(document.status)}>{labelFor(document.status)}</Badge></td>
                    <td>{labelFor(document.source)}</td>
                    <td>{directionLabel(document.direction)}</td>
                    <td>{document.quarter ?? "Not set"}</td>
                    <td><Badge tone={priorityTone(priority)}>{labelFor(priority)}</Badge></td>
                    <td>{formatBytes(document.byteSize)}</td>
                    <td>
                      <button className="secondary-button small" type="button" onClick={() => onSelect(document.documentId)}>
                        <FileText className="size-4" aria-hidden="true" />
                        Review
                      </button>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function ReviewColumn({
  client,
  counterparties,
  onClose,
  onSaved,
  selectedDocumentId
}: {
  client: AutonomoApiClient;
  counterparties: AutonomoCounterpartySummary[];
  onClose: () => void;
  onSaved: () => Promise<void>;
  selectedDocumentId: string | null;
}) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState<ReviewFormState>(emptyReviewForm);
  const [counterpartyForm, setCounterpartyForm] = useState<CounterpartyFormState>(emptyCounterpartyForm);
  const [previewFile, setPreviewFile] = useState<PreviewFileState | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  const detailQuery = useQuery({
    enabled: Boolean(selectedDocumentId),
    queryFn: () => {
      if (!selectedDocumentId) throw new Error("Select a document first.");
      return client.getDocumentDetail(selectedDocumentId);
    },
    queryKey: ["autonomo-av", "document-detail", selectedDocumentId]
  });

  useEffect(() => {
    if (!detailQuery.data) return;
    setForm(reviewFormFromDetail(detailQuery.data));
    setFormError(null);
  }, [detailQuery.data]);

  useEffect(() => {
    if (!previewFile) return;
    return () => URL.revokeObjectURL(previewFile.url);
  }, [previewFile]);

  const createCounterpartyMutation = useMutation({
    mutationFn: (payload: CounterpartyFormState) =>
      client.createCounterparty({
        kind: payload.kind,
        displayName: payload.displayName,
        taxId: optionalText(payload.taxId),
        vatId: optionalText(payload.vatId),
        country: optionalText(payload.country)?.toUpperCase() ?? null,
        notes: optionalText(payload.notes)
      }),
    onSuccess: async (response) => {
      setForm((current) => ({ ...current, counterpartyId: response.counterparty.counterpartyId }));
      setCounterpartyForm(emptyCounterpartyForm);
      toast.success("Counterparty created", { description: response.counterparty.displayName });
      await queryClient.invalidateQueries({ queryKey: ["autonomo-av", "counterparties"] });
    },
    onError: (error) => toast.error("Counterparty could not be created", { description: error.message })
  });

  const saveMutation = useMutation({
    mutationFn: (status: AutonomoManualDocumentStatus) => {
      if (!selectedDocumentId) throw new Error("Select a document first.");
      const payload = reviewPayloadFromForm(form, status);
      return client.saveDocumentReview(selectedDocumentId, payload);
    },
    onSuccess: async (detail) => {
      toast.success("Review saved", { description: detail.document.title ?? detail.document.originalFilename });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["autonomo-av", "documents"] }),
        queryClient.invalidateQueries({ queryKey: ["autonomo-av", "document-detail", detail.document.documentId] }),
        queryClient.invalidateQueries({ queryKey: ["autonomo-av", "quarter-summary"] }),
        onSaved()
      ]);
    },
    onError: (error) => {
      setFormError(error.message);
      toast.error("Review could not be saved", { description: error.message });
    }
  });

  const fileMutation = useMutation({
    mutationFn: () => {
      if (!detailQuery.data) throw new Error("Load a document before previewing the file.");
      return client.getDocumentFile(detailQuery.data.document.documentId, detailQuery.data.document.originalFilename);
    },
    onSuccess: (file) => {
      setPreviewFile({
        url: URL.createObjectURL(file.blob),
        filename: file.filename,
        contentType: file.contentType
      });
    },
    onError: (error) => toast.error("Original file could not be loaded", { description: error.message })
  });

  if (!selectedDocumentId) {
    return (
      <aside className="panel review-column review-empty">
        <FileText className="size-8 text-muted-foreground" aria-hidden="true" />
        <h2 className="section-title">Select a document</h2>
        <p className="section-copy">Choose an inbox item to review the AI draft, correct fields, and save a human-owned record.</p>
      </aside>
    );
  }

  const detail = detailQuery.data ?? null;
  const draft = detail?.latestDraft ?? null;

  const saveWithStatus = (status: AutonomoManualDocumentStatus) => {
    const error = validateReviewForm(form, status);
    setFormError(error);
    if (error) return;
    saveMutation.mutate(status);
  };

  return (
    <aside className="panel review-column" aria-labelledby="review-title">
      <div className="review-column-header">
        <div className="min-w-0">
          <h2 id="review-title" className="section-title">Review document</h2>
          <p className="section-copy">{detail?.document.originalFilename ?? "Loading document"}</p>
        </div>
        <button className="icon-button" type="button" onClick={onClose} aria-label="Close document review">
          <X className="size-4" />
        </button>
      </div>

      {detailQuery.isFetching ? <InlineAlert title="Loading document">Fetching safe workspace-scoped detail.</InlineAlert> : null}
      {detailQuery.error ? <InlineAlert tone="danger" title="Could not load document">{detailQuery.error.message}</InlineAlert> : null}
      {formError ? <InlineAlert tone="danger" title="Review needs one correction">{formError}</InlineAlert> : null}

      {detail ? (
        <>
          <div className="review-summary">
            <Badge tone={statusTone(detail.document.status)}>{labelFor(detail.document.status)}</Badge>
            <span>{formatDate(detail.document.createdAt)}</span>
            <span>{formatBytes(detail.document.byteSize)}</span>
          </div>

          <div className="review-actions">
            <button className="secondary-button" type="button" onClick={() => fileMutation.mutate()} disabled={fileMutation.isPending}>
              {fileMutation.isPending ? <Loader2 className="size-4 animate-spin" /> : <ArrowDownToLine className="size-4" />}
              Preview file
            </button>
            <a className={previewFile ? "secondary-button" : "secondary-button disabled-link"} href={previewFile?.url ?? "#"} download={previewFile?.filename} aria-disabled={!previewFile}>
              <ArrowDownToLine className="size-4" aria-hidden="true" />
              Download
            </a>
          </div>

          {previewFile ? <FilePreview file={previewFile} /> : null}

          <DraftPanel detail={detail} onApply={() => setForm(reviewFormFromDraft(form, detail))} />

          <div className="form-grid">
            <InputField label="Title" value={form.title} onChange={(value) => setForm({ ...form, title: value })} />
            <SelectField label="Accepted status" value={form.status} onChange={(value) => setForm({ ...form, status: value as AutonomoManualDocumentStatus })}>
              {manualStatuses.map((status) => <option key={status} value={status}>{labelFor(status)}</option>)}
            </SelectField>
            <SelectField label="Direction" value={form.direction} onChange={(value) => setForm({ ...form, direction: value as AutonomoDocumentDirection })}>
              {directions.filter((item) => item !== "all").map((direction) => <option key={direction} value={direction}>{labelFor(direction)}</option>)}
            </SelectField>
            <SelectField label="Type" value={form.documentType} onChange={(value) => setForm({ ...form, documentType: value as AutonomoReviewedDocumentType })}>
              {reviewedDocumentTypes.map((type) => <option key={type} value={type}>{labelFor(type)}</option>)}
            </SelectField>
            <InputField label="Date" type="date" value={form.documentDate} onChange={(value) => setForm({ ...form, documentDate: value, quarter: value ? quarterForDate(value) : form.quarter })} />
            <InputField label="Quarter" value={form.quarter} onChange={(value) => setForm({ ...form, quarter: value })} />
            <SelectField label="Counterparty" value={form.counterpartyId} onChange={(value) => setForm({ ...form, counterpartyId: value })}>
              <option value="">No counterparty</option>
              {counterparties.map((counterparty) => <option key={counterparty.counterpartyId} value={counterparty.counterpartyId}>{counterparty.displayName}</option>)}
            </SelectField>
            <InputField label="Currency" value={form.currency} onChange={(value) => setForm({ ...form, currency: value.toUpperCase() })} />
            <InputField label="Base" value={form.baseAmount} onChange={(value) => setForm({ ...form, baseAmount: value })} />
            <InputField label="VAT" value={form.vatAmount} onChange={(value) => setForm({ ...form, vatAmount: value })} />
            <InputField label="Total" value={form.totalAmount} onChange={(value) => setForm({ ...form, totalAmount: value })} />
            <InputField label="Category" value={form.category} onChange={(value) => setForm({ ...form, category: value })} />
          </div>
          <TextAreaField label="Notes" value={form.notes} onChange={(value) => setForm({ ...form, notes: value })} />

          <CounterpartyCreatePanel
            form={counterpartyForm}
            isCreating={createCounterpartyMutation.isPending}
            onChange={setCounterpartyForm}
            onCreate={() => createCounterpartyMutation.mutate(counterpartyForm)}
          />

          <div className="review-submit-row">
            <button className="primary-button" type="button" disabled={saveMutation.isPending} onClick={() => saveWithStatus("reviewed")}>
              {saveMutation.isPending ? <Loader2 className="size-4 animate-spin" /> : <CheckCircle2 className="size-4" />}
              Save reviewed
            </button>
            <button className="secondary-button" type="button" disabled={saveMutation.isPending} onClick={() => saveWithStatus("queued")}>
              <RotateCcw className="size-4" />
              Ask reprocess
            </button>
            <button className="secondary-button" type="button" disabled={saveMutation.isPending} onClick={() => saveWithStatus("duplicate")}>
              Mark duplicate
            </button>
            <button className="secondary-button" type="button" disabled={saveMutation.isPending} onClick={() => saveWithStatus("ignored")}>
              Ignore
            </button>
          </div>
        </>
      ) : null}
    </aside>
  );
}

function DraftPanel({ detail, onApply }: { detail: AutonomoDocumentDetailResponse; onApply: () => void }) {
  const draft = detail.latestDraft;

  return (
    <div className="draft-panel">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="subsection-title">AI draft</h3>
          <p className="section-copy">Draft only. Reviewed records are created by the human save action.</p>
        </div>
        <Badge tone={draft ? priorityTone(draft.priority ?? priorityForDocument(detail.document, detail)) : "muted"}>{draft ? confidencePercent(draft) : "No draft"}</Badge>
      </div>
      {draft ? (
        <>
          <dl className="draft-grid">
            <DraftValue label="Direction" value={labelFor(draft.extraction.fieldValues.direction)} />
            <DraftValue label="Type" value={labelFor(draft.extraction.fieldValues.documentType)} />
            <DraftValue label="Date" value={draft.extraction.fieldValues.documentDate ?? "Not set"} />
            <DraftValue label="Counterparty" value={draft.extraction.fieldValues.counterpartyName ?? "Not set"} />
            <DraftValue label="Total" value={formatMoney(draft.extraction.fieldValues.totalAmount, draft.extraction.fieldValues.currency ?? "EUR")} />
            <DraftValue label="Action" value={labelFor(draft.recommendedAction ?? "review")} />
          </dl>
          {draft.extraction.reviewReasons.length > 0 ? (
            <div className="review-reasons">
              {draft.extraction.reviewReasons.map((reason) => <Badge key={reason} tone="warning">{labelFor(reason)}</Badge>)}
            </div>
          ) : null}
          <button className="secondary-button" type="button" onClick={onApply}>
            Apply draft fields
          </button>
        </>
      ) : (
        <p className="section-copy">No structured draft is available yet. You can still classify, ignore, or ask for reprocessing.</p>
      )}
    </div>
  );
}

function CounterpartyCreatePanel({
  form,
  isCreating,
  onChange,
  onCreate
}: {
  form: CounterpartyFormState;
  isCreating: boolean;
  onChange: (form: CounterpartyFormState) => void;
  onCreate: () => void;
}) {
  return (
    <div className="counterparty-create">
      <div>
        <h3 className="subsection-title">Create counterparty</h3>
        <p className="section-copy">Minimal supplier/customer record for this review.</p>
      </div>
      <div className="form-grid compact">
        <SelectField label="Kind" value={form.kind} onChange={(value) => onChange({ ...form, kind: value as AutonomoCounterpartyKind })}>
          {counterpartyKinds.map((kind) => <option key={kind} value={kind}>{labelFor(kind)}</option>)}
        </SelectField>
        <InputField label="Name" value={form.displayName} onChange={(value) => onChange({ ...form, displayName: value })} />
        <InputField label="Tax ID" value={form.taxId} onChange={(value) => onChange({ ...form, taxId: value })} />
        <InputField label="VAT ID" value={form.vatId} onChange={(value) => onChange({ ...form, vatId: value })} />
        <InputField label="Country" value={form.country} onChange={(value) => onChange({ ...form, country: value.toUpperCase() })} />
      </div>
      <button className="secondary-button" type="button" disabled={isCreating || form.displayName.trim().length === 0} onClick={onCreate}>
        {isCreating ? <Loader2 className="size-4 animate-spin" /> : <Plus className="size-4" />}
        Create and select
      </button>
    </div>
  );
}

function QuarterScreen({
  documents,
  isLoading,
  quarter,
  setQuarter,
  summary
}: {
  documents: AutonomoDocumentListItem[];
  isLoading: boolean;
  quarter: string;
  setQuarter: (quarter: string) => void;
  summary: AutonomoQuarterSummaryResponse | null;
}) {
  const pendingCount = documents.filter((document) => document.quarter === quarter && (document.status === "queued" || document.status === "processing" || document.status === "drafted")).length;
  const needsReviewCount = documents.filter((document) => document.quarter === quarter && document.status === "needs_review").length;
  const failedCount = documents.filter((document) => document.quarter === quarter && (document.status === "failed" || document.status === "quarantined")).length;
  const primaryCurrency = summary?.currencies[0] ?? null;

  return (
    <section className="grid gap-4">
      <div className="panel route-panel">
        <div>
          <h2 className="section-title">Quarter view</h2>
          <p className="section-copy">Reviewed records are the only source for totals. Pending and needs-review documents stay outside the fiscal buckets.</p>
        </div>
        <InputField label="Quarter" value={quarter} onChange={setQuarter} />
      </div>

      <div className="metric-row">
        <Metric label="Reviewed records" value={summary?.reviewedDocumentCount ?? 0} tone="success" />
        <Metric label="Pending" value={pendingCount} tone="muted" />
        <Metric label="Needs review" value={needsReviewCount} tone="warning" />
        <Metric label="Failed/quarantine" value={failedCount} tone="danger" />
      </div>

      <div className="quarter-grid">
        <section className="panel">
          <div className="flex items-center justify-between gap-3">
            <h2 className="section-title">Reviewed totals</h2>
            {isLoading ? <Badge tone="muted">Loading</Badge> : null}
          </div>
          <div className="totals-grid">
            <SummaryTile label="Sales" value={formatMoney(primaryCurrency?.sale.totalAmount, primaryCurrency?.currency ?? "EUR")} detail={`${primaryCurrency?.sale.count ?? 0} docs`} />
            <SummaryTile label="Purchases" value={formatMoney(primaryCurrency?.purchase.totalAmount, primaryCurrency?.currency ?? "EUR")} detail={`${primaryCurrency?.purchase.count ?? 0} docs`} />
            <SummaryTile label="Net" value={formatMoney(primaryCurrency?.netTotalAmount, primaryCurrency?.currency ?? "EUR")} detail={primaryCurrency?.currency ?? "EUR"} />
          </div>
        </section>

        <section className="panel">
          <h2 className="section-title">Breakdown</h2>
          <div className="document-table-wrap">
            <table className="document-table compact-table">
              <thead>
                <tr>
                  <th>Currency</th>
                  <th>Direction</th>
                  <th>Type</th>
                  <th>Count</th>
                  <th>Total</th>
                </tr>
              </thead>
              <tbody>
                {summary && summary.byDocumentType.length > 0 ? (
                  summary.byDocumentType.map((item) => (
                    <tr key={`${item.currency}-${item.direction}-${item.documentType}`}>
                      <td>{item.currency}</td>
                      <td>{labelFor(item.direction)}</td>
                      <td>{labelFor(item.documentType)}</td>
                      <td>{item.count}</td>
                      <td>{formatMoney(item.totalAmount, item.currency)}</td>
                    </tr>
                  ))
                ) : (
                  <tr><td colSpan={5}>No reviewed records for this quarter.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </section>
  );
}

function SettingsScreen({
  emailIntake,
  workspace
}: {
  emailIntake: AutonomoEmailIntakeSettings;
  workspace: { displayName: string; country: string; timezone: string; defaultCurrency: string; status: string } | null;
}) {
  return (
    <section className="settings-grid">
      <div className="panel">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="section-title">Workspace</h2>
            <p className="section-copy">Basics returned from Autonomo workspace bootstrap.</p>
          </div>
          <Settings className="size-5 text-muted-foreground" aria-hidden="true" />
        </div>
        <dl className="settings-list">
          <InfoRow label="Name" value={workspace?.displayName ?? "Loading"} />
          <InfoRow label="Country" value={workspace?.country ?? "Not set"} />
          <InfoRow label="Timezone" value={workspace?.timezone ?? "Not set"} />
          <InfoRow label="Currency" value={workspace?.defaultCurrency ?? "EUR"} />
          <InfoRow label="Status" value={workspace?.status ? labelFor(workspace.status) : "Loading"} />
        </dl>
      </div>

      {emailIntake.enabled ? (
        <div className="panel email-panel">
          <div>
            <h2 className="section-title">Email intake</h2>
            <p className="section-copy">Optional private alias for forwarding business documents when the feature is enabled.</p>
          </div>
          <div className="alias-row">
            <code>{emailIntake.alias}</code>
            <button
              className="icon-button"
              type="button"
              aria-label="Copy private email alias"
              onClick={() => {
                if (emailIntake.alias) {
                  void navigator.clipboard.writeText(emailIntake.alias);
                  toast.success("Alias copied");
                }
              }}
            >
              <Copy className="size-4" />
            </button>
          </div>
          <Badge tone={emailIntake.status === "active" ? "success" : "warning"}>{labelFor(emailIntake.status)}</Badge>
        </div>
      ) : null}
    </section>
  );
}

function FilePreview({ file }: { file: PreviewFileState }) {
  const isImage = file.contentType.startsWith("image/");

  return (
    <div className="file-preview">
      <div className="cell-subtitle">{file.filename}</div>
      {isImage ? <img src={file.url} alt="" /> : <iframe title={`Preview ${file.filename}`} src={file.url} />}
    </div>
  );
}

function Metric({ label, value, tone }: { label: string; value: number | string; tone: "danger" | "info" | "muted" | "success" | "warning" }) {
  return (
    <div className={`metric metric-${tone}`}>
      <div className="metric-label">{label}</div>
      <div className="metric-value">{value}</div>
    </div>
  );
}

function SummaryTile({ detail, label, value }: { detail: string; label: string; value: string }) {
  return (
    <div className="summary-tile">
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </div>
  );
}

function DraftValue({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function Badge({ children, tone = "muted" }: { children: ReactNode; tone?: "danger" | "info" | "muted" | "success" | "warning" }) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}

function InlineAlert({ children, title, tone = "muted" }: { children: ReactNode; title: string; tone?: "danger" | "muted" | "warning" }) {
  return (
    <div className={`inline-alert inline-alert-${tone}`}>
      <AlertTriangle className="size-4" aria-hidden="true" />
      <div>
        <div className="font-semibold">{title}</div>
        <div>{children}</div>
      </div>
    </div>
  );
}

function SelectField({ children, label, onChange, value }: { children: ReactNode; label: string; onChange: (value: string) => void; value: string }) {
  return (
    <label className="field-label">
      <span>{label}</span>
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        {children}
      </select>
    </label>
  );
}

function InputField({
  label,
  onChange,
  placeholder,
  type = "text",
  value
}: {
  label: string;
  onChange: (value: string) => void;
  placeholder?: string;
  type?: string;
  value: string;
}) {
  return (
    <label className="field-label">
      <span>{label}</span>
      <input type={type} value={value} placeholder={placeholder} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}

function TextAreaField({ label, onChange, value }: { label: string; onChange: (value: string) => void; value: string }) {
  return (
    <label className="field-label field-wide">
      <span>{label}</span>
      <textarea value={value} rows={3} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function usePathRoute(): AppRoute {
  const [path, setPath] = useState(() => window.location.pathname);

  useEffect(() => {
    const onNavigation = () => setPath(window.location.pathname);
    window.addEventListener("popstate", onNavigation);
    return () => window.removeEventListener("popstate", onNavigation);
  }, []);

  if (path.startsWith("/sign-in")) return "sign-in";
  if (path.startsWith("/quarter")) return "quarter";
  if (path.startsWith("/settings")) return "settings";
  return "inbox";
}

function pathForRoute(route: AppRoute) {
  if (route === "sign-in") return "/sign-in";
  if (route === "quarter") return "/quarter";
  if (route === "settings") return "/settings";
  return "/";
}

function authBadgeTone(authSession: AutonomoAuthSession): "danger" | "info" | "muted" | "success" | "warning" {
  if (authSession.authMode === "account-av") return authSession.isSignedIn ? "success" : "warning";
  if (authSession.authMode === "dev-bearer") return "warning";
  if (authSession.authMode === "missing-config") return "danger";
  return "muted";
}

function currentReturnPath() {
  return `${window.location.pathname}${window.location.search}${window.location.hash}`;
}

function safeReturnTo(search: string) {
  const returnTo = new URLSearchParams(search).get("returnTo")?.trim();
  if (!returnTo || !returnTo.startsWith("/") || returnTo.startsWith("//")) {
    return null;
  }
  return returnTo;
}

function metricsFromDocuments(documents: AutonomoDocumentListItem[]) {
  return {
    drafted: documents.filter((document) => document.status === "drafted").length,
    failed: documents.filter((document) => document.status === "failed" || document.status === "quarantined").length,
    needsReview: documents.filter((document) => document.status === "needs_review").length,
    queued: documents.filter((document) => document.status === "queued" || document.status === "uploaded" || document.status === "processing").length
  };
}

function reviewFormFromDetail(detail: AutonomoDocumentDetailResponse): ReviewFormState {
  const draft = detail.latestDraft?.extraction.fieldValues;
  const reviewed = detail.reviewedRecord;
  return {
    title: detail.document.title ?? detail.document.originalFilename,
    status: detail.document.status === "reviewed" || detail.document.status === "duplicate" || detail.document.status === "ignored" || detail.document.status === "failed" || detail.document.status === "queued"
      ? detail.document.status
      : "needs_review",
    direction: reviewed?.direction ?? draft?.direction ?? detail.document.direction,
    documentType: reviewed?.documentType ?? reviewedTypeFromDocumentType(draft?.documentType ?? detail.document.documentType),
    documentDate: reviewed?.recordDate ?? draft?.documentDate ?? detail.document.documentDate ?? "",
    quarter: reviewed?.quarter ?? draft?.quarter ?? detail.document.quarter ?? currentQuarter(),
    counterpartyId: reviewed?.counterpartyId ?? draft?.counterpartyId ?? detail.document.counterpartyId ?? "",
    currency: reviewed?.currency ?? draft?.currency ?? "EUR",
    baseAmount: reviewed?.baseAmount ?? draft?.baseAmount ?? "0.00",
    vatAmount: reviewed?.vatAmount ?? draft?.vatAmount ?? "0.00",
    totalAmount: reviewed?.totalAmount ?? draft?.totalAmount ?? "0.00",
    category: reviewed?.category ?? draft?.category ?? "",
    notes: reviewed?.notes ?? draft?.notes ?? ""
  };
}

function reviewFormFromDraft(current: ReviewFormState, detail: AutonomoDocumentDetailResponse): ReviewFormState {
  const draft = detail.latestDraft?.extraction.fieldValues;
  if (!draft) return current;
  return {
    ...current,
    title: detail.document.title ?? current.title,
    direction: draft.direction,
    documentType: reviewedTypeFromDocumentType(draft.documentType),
    documentDate: draft.documentDate ?? current.documentDate,
    quarter: draft.quarter ?? current.quarter,
    counterpartyId: draft.counterpartyId ?? current.counterpartyId,
    currency: draft.currency ?? current.currency,
    baseAmount: draft.baseAmount ?? current.baseAmount,
    vatAmount: draft.vatAmount ?? current.vatAmount,
    totalAmount: draft.totalAmount ?? current.totalAmount,
    category: draft.category ?? current.category,
    notes: draft.notes ?? current.notes
  };
}

function reviewPayloadFromForm(form: ReviewFormState, status: AutonomoManualDocumentStatus) {
  const counterpartyId = optionalText(form.counterpartyId);
  return {
    status,
    title: optionalText(form.title),
    direction: form.direction,
    documentType: form.documentType,
    documentDate: optionalText(form.documentDate),
    quarter: optionalText(form.quarter),
    counterpartyId,
    reviewedRecord:
      status === "reviewed"
        ? {
            counterpartyId,
            direction: form.direction,
            documentType: form.documentType,
            recordDate: form.documentDate,
            quarter: form.quarter,
            currency: form.currency.toUpperCase(),
            baseAmount: form.baseAmount,
            vatAmount: form.vatAmount,
            totalAmount: form.totalAmount,
            category: optionalText(form.category),
            notes: optionalText(form.notes)
          }
        : null
  };
}

function validateReviewForm(form: ReviewFormState, status: AutonomoManualDocumentStatus) {
  if (status !== "reviewed") return null;
  if (!form.documentDate) return "Reviewed documents need a document date.";
  if (!form.quarter) return "Reviewed documents need a quarter.";
  if (quarterForDate(form.documentDate) !== form.quarter) return "Quarter must match the document date.";
  if (!/^[A-Z]{3}$/.test(form.currency)) return "Currency must be a 3-letter ISO code.";
  if (!isValidMoney(form.baseAmount) || !isValidMoney(form.vatAmount) || !isValidMoney(form.totalAmount)) {
    return "Base, VAT, and total must be non-negative amounts with up to 2 decimals.";
  }
  return null;
}

function clampLimit(value: string) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 25;
  return Math.min(Math.max(Math.trunc(parsed), 1), 100);
}
