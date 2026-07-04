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
  getAutonomoAccountManagementUrl,
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
  type AutonomoAppAccess,
  type AutonomoBusinessProfileKind,
  type AutonomoCounterpartyKind,
  type AutonomoCounterpartyResponse,
  type AutonomoCounterpartySummary,
  type AutonomoDocumentDetailResponse,
  type AutonomoDocumentFileDownload,
  type AutonomoDocumentDirection,
  type AutonomoDocumentListItem,
  type AutonomoDocumentStatus,
  type AutonomoDocumentType,
  type AutonomoEmailIntakeSettings,
  type AutonomoManualDocumentStatus,
  type AutonomoPriority,
  type AutonomoQuarterSummaryResponse,
  type AutonomoReviewedDocumentType,
  type AutonomoUploadCompletionResponse,
  type AutonomoWorkspaceBusinessProfile,
  type AutonomoWorkspaceBusinessProfileUpdateRequest,
  type AutonomoWorkspaceSummary
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
const sources = [
  "all",
  "web_upload",
  "ios_camera",
  "ios_files",
  "ios_share",
  "macos_files",
  "macos_drag_drop",
  "macos_share",
  "macos_service"
] as const;
const priorities: Array<AutonomoPriority | "all"> = ["all", "low", "normal", "interesting", "urgent", "blocking"];
const manualStatuses: AutonomoManualDocumentStatus[] = ["queued", "needs_review", "reviewed", "duplicate", "ignored", "failed"];
const reviewedDocumentTypes: AutonomoReviewedDocumentType[] = ["invoice", "ticket", "receipt", "other"];
const counterpartyKinds: AutonomoCounterpartyKind[] = ["supplier", "customer", "both", "unknown"];
const businessProfileKinds: AutonomoBusinessProfileKind[] = ["self_employed", "company", "other"];
const uploadAccept = `${autonomoUploadContentTypeValues.join(",")},.pdf,.jpg,.jpeg,.png,.webp,.heic,.heif`;

type PublicRoute = "delete-account" | "privacy" | "support" | "terms";
type AppRoute = "inbox" | "quarter" | "settings" | "sign-in" | PublicRoute;
type SignedInRoute = Exclude<AppRoute, "sign-in" | PublicRoute>;

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

const supportMailto = "mailto:support@avalsys.com?subject=Autonomo%20AV%20support";

const publicPages: Record<PublicRoute, {
  actionBody: string;
  actionTitle: string;
  primaryHref: string;
  primaryLabel: string;
  sections: Array<{ body: string[]; title: string }>;
  summary: string;
  title: string;
}> = {
  "delete-account": {
    title: "Delete account",
    summary: "Autonomo AV uses Account AV for sign-in, account identity, and account deletion requests.",
    sections: [
      {
        title: "How deletion works",
        body: [
          "Sign in with the Account AV user that owns the Autonomo AV workspace, then open the account deletion flow from the app or Account AV management.",
          "Because Account AV can be shared across Avalsys apps, the deletion flow may show linked apps, active billing, or other consequences before final confirmation."
        ]
      },
      {
        title: "Autonomo AV data",
        body: [
          "Deletion can include the Autonomo AV workspace, uploaded business documents, AI draft metadata, reviewed records, and related account identifiers.",
          "Some operational records may be retained when needed for security, abuse prevention, billing, legal compliance, or unresolved support cases."
        ]
      }
    ],
    actionTitle: "Need help deleting an account?",
    actionBody: "If you cannot sign in, contact support from the email address attached to the Account AV user and include Autonomo AV in the subject.",
    primaryHref: supportMailto,
    primaryLabel: "Contact support"
  },
  privacy: {
    title: "Privacy policy",
    summary: "Autonomo AV handles business documents so a signed-in user can queue, classify, review, and organize them.",
    sections: [
      {
        title: "Data we process",
        body: [
          "Autonomo AV may process uploaded files, filenames, file metadata, document classifications, extracted draft fields, reviewed records, workspace settings, account identifiers, and support messages.",
          "The app uses Account AV for authentication and may receive session identifiers needed to keep uploads scoped to the correct workspace."
        ]
      },
      {
        title: "AI document handling",
        body: [
          "Uploaded documents may be analyzed by AI systems to propose classifications, extraction fields, urgency, and review actions.",
          "AI output is a draft for human review. It is not tax, legal, accounting, or financial advice, and it does not submit official filings."
        ]
      },
      {
        title: "Sharing and retention",
        body: [
          "We do not sell personal data. We use service providers only where needed to run authentication, hosting, storage, processing, observability, support, and security.",
          "Business documents and derived records are retained while the workspace is active, unless deleted through supported account or workspace deletion processes."
        ]
      }
    ],
    actionTitle: "Privacy questions",
    actionBody: "Contact support for privacy questions, access requests, or deletion questions related to Autonomo AV.",
    primaryHref: supportMailto,
    primaryLabel: "Contact support"
  },
  support: {
    title: "Support",
    summary: "Contact Avalsys support for Autonomo AV account, upload, privacy, and deletion questions.",
    sections: [
      {
        title: "What to include",
        body: [
          "Include the Account AV email address, the affected Autonomo AV workspace if known, the device or browser, and a short description of the issue.",
          "Do not send unnecessary private documents in the first support email. If a file is needed, support will ask for the safest next step."
        ]
      },
      {
        title: "Business document issues",
        body: [
          "For upload or AI draft issues, include the approximate upload time, source such as iPhone share or web upload, and the filename if it is safe to share.",
          "Autonomo AV support can help with app behavior, but does not provide tax, legal, accounting, or financial advice."
        ]
      }
    ],
    actionTitle: "Contact",
    actionBody: "Use email support for now. A fuller support portal can replace this page later without changing the App Store URL.",
    primaryHref: supportMailto,
    primaryLabel: "Email support"
  },
  terms: {
    title: "Terms of service",
    summary: "These terms describe the first Autonomo AV service boundary for document intake, AI drafts, and manual review.",
    sections: [
      {
        title: "Service scope",
        body: [
          "Autonomo AV helps signed-in users collect business documents, queue them for processing, review AI drafts, and organize reviewed records.",
          "The service does not replace professional advice and does not file taxes, submit official forms, make payments, or act as an accountant."
        ]
      },
      {
        title: "User responsibility",
        body: [
          "You are responsible for reviewing extracted fields, document classifications, totals, dates, counterparties, and any action you take outside the app.",
          "Only upload documents you are allowed to process, and do not use the service for illegal, abusive, or unauthorized content."
        ]
      },
      {
        title: "Availability and changes",
        body: [
          "Autonomo AV may change while it is prepared for private use, TestFlight, and later production releases.",
          "Access may depend on Account AV identity, backend availability, plan eligibility, security checks, and product readiness."
        ]
      }
    ],
    actionTitle: "Questions about these terms",
    actionBody: "Contact support before relying on Autonomo AV for a workflow that has legal, tax, accounting, or financial consequences.",
    primaryHref: supportMailto,
    primaryLabel: "Contact support"
  }
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
  const appRoute: SignedInRoute = route === "sign-in" || isPublicRoute(route) ? "inbox" : route;
  const shouldLoadAccess =
    !isPublicRoute(route)
    && authSession.isLoaded
    && authSession.authMode !== "missing-config"
    && (useFixtures || authSession.isSignedIn);
  const accessQuery = useQuery({
    enabled: shouldLoadAccess,
    queryFn: () => client.fetchMeAccess(),
    queryKey: ["autonomo-av", "access", authSession.sessionId, useFixtures],
    staleTime: 60_000
  });
  const autonomoAccess = accessQuery.data?.apps.find((app: AutonomoAppAccess) => app.appId === "autonomoav");
  const hasProAccess = useFixtures || hasAutonomoProAccess(autonomoAccess);

  if (isPublicRoute(route)) {
    return (
      <AppShell
        currentPath={pathForRoute(route)}
        footerLabels={autonomoFooterLabels}
        labels={autonomoShellLabels}
        navLinks={autonomoNavLinks}
        product={autonomoProductConfig}
      >
        <AutonomoPublicPage route={route} />
      </AppShell>
    );
  }

  if (!authSession.isLoaded) {
    return <AuthSkeleton />;
  }

  if (!useFixtures && authSession.authMode === "missing-config") {
    return <AuthConfigurationMissing />;
  }

  if (!useFixtures && !authSession.isSignedIn) {
    return <AutonomoSignInScreen authSession={authSession} route={route} />;
  }

  if (shouldLoadAccess && accessQuery.isLoading) {
    return <AuthSkeleton />;
  }

  if (!hasProAccess) {
    return (
      <AppShell
        currentPath={pathForRoute(appRoute)}
        footerLabels={autonomoFooterLabels}
        labels={autonomoShellLabels}
        navLinks={autonomoNavLinks}
        product={autonomoProductConfig}
      >
        <AutonomoProRequiredScreen
          access={autonomoAccess}
          authSession={authSession}
          error={accessQuery.error instanceof Error ? accessQuery.error : null}
          isRefreshing={accessQuery.isFetching}
          onRefresh={() => void accessQuery.refetch()}
        />
      </AppShell>
    );
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

function hasAutonomoProAccess(access: AutonomoAppAccess | undefined) {
  return Boolean(
    access
      && access.accessMode === "signedInPro"
      && access.planTier === "pro"
      && access.capabilities.canUseBackend
      && access.capabilities.canUsePremiumFeatures
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
  route: SignedInRoute;
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
        source: filters.source === "all" ? undefined : filters.source,
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
      filters.source,
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

  const documents: AutonomoDocumentListItem[] = documentsQuery.data?.documents ?? [];
  const counterparties: AutonomoCounterpartySummary[] = counterpartiesQuery.data?.counterparties ?? [];
  const workspace = workspaceQuery.data?.workspace ?? null;
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
          workspace={workspace}
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
          client={client}
          emailIntake={emailIntake}
          onWorkspaceUpdated={refreshAll}
          workspace={workspace}
        />
      ) : null}
    </section>
  );
}

function AutonomoPublicPage({ route }: { route: PublicRoute }) {
  const page = publicPages[route];

  return (
    <main className="legal-page" aria-labelledby="legal-page-title">
      <section className="legal-hero">
        <Badge tone="info">Autonomo AV</Badge>
        <h1 id="legal-page-title">{page.title}</h1>
        <p>{page.summary}</p>
        <div className="legal-meta">Last updated: July 1, 2026</div>
      </section>

      <div className="legal-grid">
        {page.sections.map((section) => (
          <section className="panel legal-section" key={section.title}>
            <h2 className="section-title">{section.title}</h2>
            {section.body.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
          </section>
        ))}
      </div>

      <section className="panel legal-section">
        <h2 className="section-title">{page.actionTitle}</h2>
        <p>{page.actionBody}</p>
        <div className="legal-actions">
          <a className="primary-button" href={page.primaryHref}>{page.primaryLabel}</a>
          <a className="secondary-button" href="/">Open inbox</a>
        </div>
      </section>
    </main>
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

function AutonomoProRequiredScreen({
  access,
  authSession,
  error,
  isRefreshing,
  onRefresh
}: {
  access: AutonomoAppAccess | undefined;
  authSession: AutonomoAuthSession;
  error: Error | null;
  isRefreshing: boolean;
  onRefresh: () => void;
}) {
  const managementUrl = getAutonomoAccountManagementUrl("/apps/autonomoav")
    ?? getAutonomoAccountManagementUrl()
    ?? autonomoProductConfig.links.suite?.href;

  return (
    <main className="autonomo-auth-page">
      <section className="auth-panel" aria-labelledby="pro-required-title">
        <div className="auth-mark" aria-hidden="true">
          <AlertTriangle className="size-5" />
        </div>
        <Badge tone={error ? "danger" : "warning"}>{error ? "Access check failed" : "Pro required"}</Badge>
        <h1 id="pro-required-title">Autonomo AV Pro is required</h1>
        <p>
          {error
            ? error.message
            : "Your Account AV session is signed in, but this workspace only opens after Autonomo AV Pro is active."}
        </p>
        <dl className="auth-config-list">
          <div><dt>Session</dt><dd>{authSession.statusLabel}</dd></div>
          <div><dt>Access</dt><dd>{access ? labelFor(access.accessMode) : "Not available"}</dd></div>
        </dl>
        <div className="auth-actions-row">
          {managementUrl ? (
            <a className="primary-button auth-action" href={managementUrl}>
              Manage Pro
            </a>
          ) : null}
          <button className="secondary-button auth-action" type="button" onClick={onRefresh} disabled={isRefreshing}>
            {isRefreshing ? <Loader2 className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
            Refresh access
          </button>
        </div>
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
  setSelectedDocumentId,
  workspace
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
  workspace: AutonomoWorkspaceSummary | null;
}) {
  const metrics = useMemo(() => metricsFromDocuments(documents), [documents]);
  const businessProfile = workspace?.businessProfile ?? null;
  const canUpload = businessProfile?.profileStatus === "complete";

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
          {!canUpload ? (
            <BusinessProfilePanel
              client={client}
              onSaved={onRefresh}
              profile={businessProfile}
              title="Business profile"
            />
          ) : null}
          <UploadPanel canUpload={canUpload} client={client} onUploaded={onRefresh} />
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

function BusinessProfilePanel({
  client,
  onSaved,
  profile,
  title = "Business profile"
}: {
  client: AutonomoApiClient;
  onSaved: () => Promise<void>;
  profile: AutonomoWorkspaceBusinessProfile | null;
  title?: string;
}) {
  const [form, setForm] = useState(() => businessProfileFormFromProfile(profile));

  useEffect(() => {
    setForm(businessProfileFormFromProfile(profile));
  }, [profile]);

  const saveMutation = useMutation({
    mutationFn: (payload: AutonomoWorkspaceBusinessProfileUpdateRequest) => client.updateBusinessProfile(payload),
    onSuccess: async () => {
      toast.success("Business profile saved");
      await onSaved();
    },
    onError: (error: Error) => toast.error("Profile save failed", { description: error.message })
  });

  const save = () => {
    const error = validateBusinessProfileForm(form);
    if (error) {
      toast.error("Business profile incomplete", { description: error });
      return;
    }

    saveMutation.mutate({
      kind: form.kind,
      legalName: form.legalName.trim(),
      tradeName: optionalText(form.tradeName),
      taxId: optionalText(form.taxId),
      vatId: optionalText(form.vatId),
      country: form.country.trim().toUpperCase(),
      fiscalAddress: optionalText(form.fiscalAddress)
    });
  };

  const complete = profile?.profileStatus === "complete";

  return (
    <section className="panel" aria-labelledby="business-profile-title">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 id="business-profile-title" className="section-title">{title}</h2>
          <p className="section-copy">Fiscal identity lets Autonomo AV recognize whether invoices are addressed to you and score drafts with better evidence.</p>
        </div>
        <Badge tone={complete ? "success" : "warning"}>{complete ? "Complete" : "Required"}</Badge>
      </div>
      <div className="filters-grid">
        <SelectField label="Type" value={form.kind} onChange={(value) => setForm({ ...form, kind: value as AutonomoBusinessProfileKind })}>
          {businessProfileKinds.map((kind) => <option key={kind} value={kind}>{labelFor(kind)}</option>)}
        </SelectField>
        <InputField label="Legal name" value={form.legalName} onChange={(value) => setForm({ ...form, legalName: value })} />
        <InputField label="Trade name" value={form.tradeName} onChange={(value) => setForm({ ...form, tradeName: value })} />
        <InputField label="Tax ID" value={form.taxId} onChange={(value) => setForm({ ...form, taxId: value })} />
        <InputField label="VAT ID" value={form.vatId} onChange={(value) => setForm({ ...form, vatId: value })} />
        <InputField label="Country" value={form.country} placeholder="ES" onChange={(value) => setForm({ ...form, country: value.toUpperCase() })} />
        <InputField label="Fiscal address" value={form.fiscalAddress} onChange={(value) => setForm({ ...form, fiscalAddress: value })} />
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <button className="primary-button" type="button" disabled={saveMutation.isPending} onClick={save}>
          {saveMutation.isPending ? <Loader2 className="size-4 animate-spin" /> : <CheckCircle2 className="size-4" />}
          Save profile
        </button>
        {profile?.updatedAt ? <span className="text-sm text-muted-foreground">Updated {formatDate(profile.updatedAt)}</span> : null}
      </div>
    </section>
  );
}

function UploadPanel({ canUpload, client, onUploaded }: { canUpload: boolean; client: AutonomoApiClient; onUploaded: () => Promise<void> }) {
  const [dragActive, setDragActive] = useState(false);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const uploadMutation = useMutation<AutonomoUploadCompletionResponse, Error, File>({
    mutationFn: (file: File) => client.uploadFile(file),
    onSuccess: async (response: AutonomoUploadCompletionResponse) => {
      toast.success("Document queued", {
        description: `${response.documentId} is ready for Autonomo AV processing.`
      });
      setSelectedFile(null);
      if (inputRef.current) inputRef.current.value = "";
      await onUploaded();
    },
    onError: (error: Error) => toast.error("Upload failed", { description: error.message })
  });

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setDragActive(false);
    if (!canUpload) {
      toast.error("Business profile required", {
        description: "Complete your business profile before uploading documents."
      });
      return;
    }
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
        <p className="section-copy">
          {canUpload
            ? "Drop one PDF or image here, or choose a file. New items appear in the inbox as queued work."
            : "Complete your business profile before uploading documents."}
        </p>
      </div>
      <div
        className={dragActive && canUpload ? "drop-zone drop-zone-active" : "drop-zone"}
        onDragEnter={(event) => {
          event.preventDefault();
          setDragActive(canUpload);
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
        <button className="secondary-button" type="button" disabled={!canUpload} onClick={() => inputRef.current?.click()}>
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
          disabled={!canUpload || !selectedFile || uploadMutation.isPending}
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

  const createCounterpartyMutation = useMutation<AutonomoCounterpartyResponse, Error, CounterpartyFormState>({
    mutationFn: (payload: CounterpartyFormState) =>
      client.createCounterparty({
        kind: payload.kind,
        displayName: payload.displayName,
        taxId: optionalText(payload.taxId),
        vatId: optionalText(payload.vatId),
        country: optionalText(payload.country)?.toUpperCase() ?? null,
        notes: optionalText(payload.notes)
      }),
    onSuccess: async (response: AutonomoCounterpartyResponse) => {
      setForm((current) => ({ ...current, counterpartyId: response.counterparty.counterpartyId }));
      setCounterpartyForm(emptyCounterpartyForm);
      toast.success("Counterparty created", { description: response.counterparty.displayName });
      await queryClient.invalidateQueries({ queryKey: ["autonomo-av", "counterparties"] });
    },
    onError: (error: Error) => toast.error("Counterparty could not be created", { description: error.message })
  });

  const saveMutation = useMutation<AutonomoDocumentDetailResponse, Error, AutonomoManualDocumentStatus>({
    mutationFn: (status: AutonomoManualDocumentStatus) => {
      if (!selectedDocumentId) throw new Error("Select a document first.");
      const payload = reviewPayloadFromForm(form, status);
      return client.saveDocumentReview(selectedDocumentId, payload);
    },
    onSuccess: async (detail: AutonomoDocumentDetailResponse) => {
      toast.success("Review saved", { description: detail.document.title ?? detail.document.originalFilename });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["autonomo-av", "documents"] }),
        queryClient.invalidateQueries({ queryKey: ["autonomo-av", "document-detail", detail.document.documentId] }),
        queryClient.invalidateQueries({ queryKey: ["autonomo-av", "quarter-summary"] }),
        onSaved()
      ]);
    },
    onError: (error: Error) => {
      setFormError(error.message);
      toast.error("Review could not be saved", { description: error.message });
    }
  });

  const fileMutation = useMutation<AutonomoDocumentFileDownload, Error, void>({
    mutationFn: () => {
      if (!detailQuery.data) throw new Error("Load a document before previewing the file.");
      return client.getDocumentFile(detailQuery.data.document.documentId, detailQuery.data.document.originalFilename);
    },
    onSuccess: (file: AutonomoDocumentFileDownload) => {
      setPreviewFile({
        url: URL.createObjectURL(file.blob),
        filename: file.filename,
        contentType: file.contentType
      });
    },
    onError: (error: Error) => toast.error("Original file could not be loaded", { description: error.message })
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
  client,
  emailIntake,
  onWorkspaceUpdated,
  workspace
}: {
  client: AutonomoApiClient;
  emailIntake: AutonomoEmailIntakeSettings;
  onWorkspaceUpdated: () => Promise<void>;
  workspace: AutonomoWorkspaceSummary | null;
}) {
  return (
    <section className="settings-grid">
      <BusinessProfilePanel
        client={client}
        onSaved={onWorkspaceUpdated}
        profile={workspace?.businessProfile ?? null}
        title="Business identity"
      />

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
  if (path.startsWith("/delete-account")) return "delete-account";
  if (path.startsWith("/privacy")) return "privacy";
  if (path.startsWith("/support")) return "support";
  if (path.startsWith("/terms")) return "terms";
  if (path.startsWith("/quarter")) return "quarter";
  if (path.startsWith("/settings")) return "settings";
  return "inbox";
}

function pathForRoute(route: AppRoute) {
  if (route === "sign-in") return "/sign-in";
  if (route === "delete-account") return "/delete-account";
  if (route === "privacy") return "/privacy";
  if (route === "support") return "/support";
  if (route === "terms") return "/terms";
  if (route === "quarter") return "/quarter";
  if (route === "settings") return "/settings";
  return "/";
}

function isPublicRoute(route: AppRoute): route is PublicRoute {
  return route === "delete-account" || route === "privacy" || route === "support" || route === "terms";
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

function businessProfileFormFromProfile(profile: AutonomoWorkspaceBusinessProfile | null) {
  return {
    kind: profile?.kind ?? ("self_employed" as AutonomoBusinessProfileKind),
    legalName: profile?.legalName ?? "",
    tradeName: profile?.tradeName ?? "",
    taxId: profile?.taxId ?? "",
    vatId: profile?.vatId ?? "",
    country: profile?.country ?? "ES",
    fiscalAddress: profile?.fiscalAddress ?? ""
  };
}

function validateBusinessProfileForm(form: ReturnType<typeof businessProfileFormFromProfile>) {
  if (!form.legalName.trim()) return "Legal name is required.";
  if (!/^[A-Z]{2}$/.test(form.country.trim().toUpperCase())) return "Country must be a two-letter code such as ES.";
  if (!form.taxId.trim() && !form.vatId.trim()) return "Tax ID or VAT ID is required.";
  return null;
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
