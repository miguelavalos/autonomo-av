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
  Trash2,
  UploadCloud,
  X
} from "lucide-react";
import { useEffect, useMemo, useRef, useState, type DragEvent, type ReactNode } from "react";
import { toast } from "sonner";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge as UiBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
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
  moneyString,
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
  type AutonomoDocumentManualReviewRequest,
  type AutonomoEmailIntakeSettings,
  type AutonomoManualDocumentStatus,
  type AutonomoQuarterSummaryResponse,
  type AutonomoRecordListItem,
  type AutonomoRecordListQuery,
  type AutonomoReviewedDocumentType,
  type AutonomoUploadCompletionResponse,
  type AutonomoWorkspaceBusinessProfile,
  type AutonomoWorkspaceBusinessProfileUpdateRequest,
  type AutonomoWorkspaceSummary
} from "@/lib/autonomo-types";
import { cn } from "@/lib/utils";

const directions: Array<AutonomoDocumentDirection | "all"> = ["all", "sale", "purchase", "unknown"];
const manualStatuses: AutonomoManualDocumentStatus[] = ["queued", "needs_review", "reviewed", "duplicate", "ignored", "failed"];
const reviewedDocumentTypes: AutonomoReviewedDocumentType[] = ["invoice", "ticket", "receipt", "other"];
const counterpartyKinds: AutonomoCounterpartyKind[] = ["supplier", "customer", "both", "unknown"];
const businessProfileKinds: AutonomoBusinessProfileKind[] = ["self_employed", "company", "other"];
const uploadAccept = `${autonomoUploadContentTypeValues.join(",")},.pdf,.jpg,.jpeg,.png,.webp,.heic,.heif`;

type PublicRoute = "delete-account" | "privacy" | "support" | "terms";
type AppRoute = "records" | "intake" | "quarter" | "settings" | "sign-in" | PublicRoute;
type SignedInRoute = Exclude<AppRoute, "sign-in" | PublicRoute>;

type RecordsPeriodMode = "month" | "quarter" | "year" | "custom";
type RecordKindFilter = "all" | "sales" | "purchases" | "expenses";

type RecordFiltersState = {
  periodMode: RecordsPeriodMode;
  month: string;
  quarter: string;
  year: string;
  dateFrom: string;
  dateTo: string;
  kind: RecordKindFilter;
  counterpartyId: string;
  category: string;
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

type ManualRecordFormState = {
  title: string;
  direction: Exclude<AutonomoDocumentDirection, "unknown">;
  documentType: AutonomoReviewedDocumentType;
  recordDate: string;
  quarter: string;
  counterpartyId: string;
  newCounterpartyName: string;
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

const emptyManualRecordForm: ManualRecordFormState = {
  title: "",
  direction: "purchase",
  documentType: "invoice",
  recordDate: todayDateOnly(),
  quarter: quarterForDate(todayDateOnly()),
  counterpartyId: "",
  newCounterpartyName: "",
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
  const appRoute: SignedInRoute = route === "sign-in" || isPublicRoute(route) ? "records" : route;
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
  const canUseBackend = useFixtures || hasAutonomoBackendAccess(autonomoAccess);

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

  if (!canUseBackend) {
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
      <AutonomoSurface
        authSession={authSession}
        client={client}
        emailIntake={emailIntake}
        hasProAccess={hasProAccess}
        route={appRoute}
        useFixtures={useFixtures}
      />
    </AppShell>
  );
}

function hasAutonomoBackendAccess(access: AutonomoAppAccess | undefined) {
  return Boolean(
    access
      && access.capabilities.isSignedIn
      && access.capabilities.canUseBackend
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
  hasProAccess,
  route,
  useFixtures
}: {
  authSession: AutonomoAuthSession;
  client: AutonomoApiClient;
  emailIntake: AutonomoEmailIntakeSettings;
  hasProAccess: boolean;
  route: SignedInRoute;
  useFixtures: boolean;
}) {
  const queryClient = useQueryClient();
  const [recordFilters, setRecordFilters] = useState<RecordFiltersState>(() => defaultRecordFilters());
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
  const recordsQuery = useQuery({
    enabled: workspaceQuery.isSuccess && route === "records",
    queryFn: () => client.listRecords(recordListQueryFromFilters(recordFilters)),
    queryKey: [
      "autonomo-av",
      "records",
      recordFilters.periodMode,
      recordFilters.month,
      recordFilters.quarter,
      recordFilters.year,
      recordFilters.dateFrom,
      recordFilters.dateTo,
      recordFilters.kind,
      recordFilters.counterpartyId,
      recordFilters.category,
      recordFilters.limit
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

  const records: AutonomoRecordListItem[] = recordsQuery.data?.records ?? [];
  const allDocuments: AutonomoDocumentListItem[] = overviewDocumentsQuery.data?.documents ?? [];
  const counterparties: AutonomoCounterpartySummary[] = counterpartiesQuery.data?.counterparties ?? [];
  const workspace = workspaceQuery.data?.workspace ?? null;
  const visibleRecords = useMemo(
    () => filterRecordsByKind(records, recordFilters.kind),
    [records, recordFilters.kind]
  );
  const intakeDocuments = useMemo(
    () => allDocuments.filter(isOperationalDocument),
    [allDocuments]
  );
  const selectableDocuments = route === "intake" && hasProAccess ? intakeDocuments : [];

  useEffect(() => {
    setSelectedDocumentId(null);
  }, [route]);

  useEffect(() => {
    if (selectedDocumentId || selectableDocuments.length === 0) return;
    const firstActionable = selectableDocuments.find((document) => document.status === "needs_review" || document.status === "drafted" || document.status === "failed");
    setSelectedDocumentId((firstActionable ?? selectableDocuments[0])?.documentId ?? null);
  }, [selectedDocumentId, selectableDocuments]);

  const refreshAll = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["autonomo-av", "workspace"] }),
      queryClient.invalidateQueries({ queryKey: ["autonomo-av", "records"] }),
      queryClient.invalidateQueries({ queryKey: ["autonomo-av", "documents"] }),
      queryClient.invalidateQueries({ queryKey: ["autonomo-av", "counterparties"] }),
      queryClient.invalidateQueries({ queryKey: ["autonomo-av", "quarter-summary"] })
    ]);
  };

  const error =
    workspaceQuery.error?.message ??
    recordsQuery.error?.message ??
    overviewDocumentsQuery.error?.message ??
    counterpartiesQuery.error?.message ??
    quarterSummaryQuery.error?.message;

  return (
    <section className="autonomo-surface">
      <HeaderStrip
        authSession={authSession}
        route={route}
        useFixtures={useFixtures}
        onRefresh={() => void refreshAll()}
        isRefreshing={recordsQuery.isFetching || overviewDocumentsQuery.isFetching || quarterSummaryQuery.isFetching}
      />
      {error ? <InlineAlert tone="danger" title="Autonomo AV could not load this workspace">{error}</InlineAlert> : null}

      {route === "records" ? (
        <RecordsScreen
          client={client}
          counterparties={counterparties}
          filters={recordFilters}
          isLoading={recordsQuery.isFetching || counterpartiesQuery.isFetching}
          onFiltersChange={setRecordFilters}
          onRefresh={refreshAll}
          records={visibleRecords}
          selectedDocumentId={selectedDocumentId}
          setSelectedDocumentId={setSelectedDocumentId}
          workspace={workspace}
        />
      ) : null}

      {route === "intake" ? (
        hasProAccess ? (
          <IntakeScreen
            client={client}
            counterparties={counterparties}
            documents={intakeDocuments}
            isLoading={overviewDocumentsQuery.isFetching || counterpartiesQuery.isFetching}
            onRefresh={refreshAll}
            selectedDocumentId={selectedDocumentId}
            setSelectedDocumentId={setSelectedDocumentId}
            workspace={workspace}
          />
        ) : (
          <AiIntakeProGate />
        )
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
          <a className="secondary-button" href="/">Open records</a>
        </div>
      </section>
    </main>
  );
}

function HeaderStrip({
  authSession,
  isRefreshing,
  onRefresh,
  route,
  useFixtures
}: {
  authSession: AutonomoAuthSession;
  isRefreshing: boolean;
  onRefresh: () => void;
  route: SignedInRoute;
  useFixtures: boolean;
}) {
  const environmentLabel = useFixtures ? "Fixture" : "Live";
  const showSessionBadge = authSession.statusLabel !== environmentLabel;
  const header = headerForRoute(route);
  const HeaderIcon = header.icon;

  return (
    <Card className="autonomo-header-strip">
      <div className="min-w-0">
        <div className="flex items-center gap-2 text-sm font-medium text-muted-foreground">
          <HeaderIcon aria-hidden="true" />
          {header.label}
        </div>
        <h1 className="mt-2 text-2xl font-semibold leading-tight text-foreground">{header.title}</h1>
        <p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">
          {header.description}
        </p>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <Badge tone={useFixtures ? "warning" : "success"}>{environmentLabel}</Badge>
        {showSessionBadge ? <Badge tone={authBadgeTone(authSession)}>{authSession.statusLabel}</Badge> : null}
        <Button variant="outline" size="icon" type="button" onClick={onRefresh} aria-label="Refresh Autonomo AV">
          {isRefreshing ? <Loader2 className="animate-spin" /> : <RefreshCw />}
        </Button>
      </div>
    </Card>
  );
}

function headerForRoute(route: SignedInRoute) {
  if (route === "records") {
    return {
      description: "Manual sales, purchases, invoices, tickets, and receipts. Pro AI intake can add drafts here after review.",
      icon: FileText,
      label: "Manual register",
      title: "Records"
    };
  }

  if (route === "quarter") {
    return {
      description: "Reviewed records only. Pending intake stays out of fiscal totals until a human saves the record.",
      icon: CheckCircle2,
      label: "Fiscal summary",
      title: "Quarter"
    };
  }

  if (route === "settings") {
    return {
      description: "Manage the business identity that Autonomo AV uses to recognize documents addressed to this workspace.",
      icon: Settings,
      label: "Workspace setup",
      title: "Settings"
    };
  }

  return {
    description: "Shared Pro AI queue for web uploads, iPhone Share Extension, and macOS intake. Drafts stay out of records until review.",
    icon: Inbox,
    label: "Pro AI intake",
    title: "AI Intake"
  };
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
          <Button className="auth-action" variant="outline" type="button" onClick={onRefresh} disabled={isRefreshing}>
            {isRefreshing ? <Loader2 className="animate-spin" /> : <RefreshCw />}
            Refresh access
          </Button>
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
            ? "Open records to continue managing workspace documents."
            : "Use your Account AV session to open live records and the backend workspace."}
        </p>
        {authSession.isSignedIn ? (
          <a className="primary-button auth-action" href={fallbackRedirectUrl}>
            Open records
          </a>
        ) : (
          <AutonomoAccountSignIn fallbackRedirectUrl={fallbackRedirectUrl} />
        )}
      </section>
    </main>
  );
}

function IntakeScreen({
  client,
  counterparties,
  documents,
  isLoading,
  onRefresh,
  selectedDocumentId,
  setSelectedDocumentId,
  workspace
}: {
  client: AutonomoApiClient;
  counterparties: AutonomoCounterpartySummary[];
  documents: AutonomoDocumentListItem[];
  isLoading: boolean;
  onRefresh: () => Promise<void>;
  selectedDocumentId: string | null;
  setSelectedDocumentId: (documentId: string | null) => void;
  workspace: AutonomoWorkspaceSummary | null;
}) {
  const metrics = useMemo(() => metricsFromDocuments(documents), [documents]);
  const businessProfile = workspace?.businessProfile ?? null;
  const canUpload = businessProfile?.profileStatus === "complete";

  return (
    <div className="intake-page">
      <AiIntakeBridgePanel />

      <div className="metric-row compact-metrics">
        <Metric label="Needs review" value={metrics.needsReview} tone="warning" />
        <Metric label="Drafted" value={metrics.drafted} tone="info" />
        <Metric label="Queued" value={metrics.queued} tone="muted" />
        <Metric label="Failed" value={metrics.failed} tone="danger" />
      </div>

      <div className="intake-layout">
        <div className="grid min-w-0 gap-4">
          {!canUpload ? (
            <BusinessProfilePanel
              client={client}
              onSaved={onRefresh}
              profile={businessProfile}
              title="Minimum fiscal setup"
            />
          ) : null}
          <UploadPanel canUpload={canUpload} client={client} onUploaded={onRefresh} />
          <DocumentList
            actionLabel="Review"
            description="Documents from web, iPhone, and macOS that still need AI processing, review, retry, or a final decision."
            documents={documents}
            emptyMessage="No queued, failed, or review-ready documents."
            isLoading={isLoading}
            selectedDocumentId={selectedDocumentId}
            title="Shared AI queue"
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

function RecordsScreen({
  client,
  counterparties,
  filters,
  isLoading,
  onFiltersChange,
  onRefresh,
  records,
  selectedDocumentId,
  setSelectedDocumentId,
  workspace
}: {
  client: AutonomoApiClient;
  counterparties: AutonomoCounterpartySummary[];
  filters: RecordFiltersState;
  isLoading: boolean;
  onFiltersChange: (filters: RecordFiltersState) => void;
  onRefresh: () => Promise<void>;
  records: AutonomoRecordListItem[];
  selectedDocumentId: string | null;
  setSelectedDocumentId: (documentId: string | null) => void;
  workspace: AutonomoWorkspaceSummary | null;
}) {
  const metrics = useMemo(() => recordMetricsFromRecords(records), [records]);
  const canCreate = workspace?.businessProfile.profileStatus === "complete";
  const archiveMutation = useMutation<AutonomoDocumentDetailResponse, Error, AutonomoRecordListItem>({
    mutationFn: (record: AutonomoRecordListItem) =>
      client.saveDocumentReview(record.documentId, archivePayloadFromRecord(record)),
    onSuccess: async (detail: AutonomoDocumentDetailResponse) => {
      toast.success("Record archived", { description: detail.document.title ?? detail.document.originalFilename });
      if (selectedDocumentId === detail.document.documentId) {
        setSelectedDocumentId(null);
      }
      await onRefresh();
    },
    onError: (error: Error) => toast.error("Record could not be archived", { description: error.message })
  });

  return (
    <section className="records-management">
      {!canCreate ? (
        <BusinessProfilePanel
          client={client}
          onSaved={onRefresh}
          profile={workspace?.businessProfile ?? null}
          title="Start with minimum fiscal setup"
        />
      ) : null}

      <div className="records-overview">
        <div>
          <h2 className="section-title">Manual register</h2>
          <p className="section-copy">
            Free users can keep a clean manual book of sales, purchases, invoices, tickets, and receipts. Pro AI intake can draft records from web, iPhone, and macOS, but nothing enters this register until it is reviewed.
          </p>
        </div>
        {isLoading ? <Badge tone="muted">Loading</Badge> : <Badge tone="info">{records.length} shown</Badge>}
      </div>

      <div className="metric-row compact-metrics">
        <Metric label="Sales" value={formatMoney(metrics.salesTotal, metrics.currency)} tone="success" />
        <Metric label="Purchases" value={formatMoney(metrics.purchaseTotal, metrics.currency)} tone="info" />
        <Metric label="VAT" value={formatMoney(metrics.vatTotal, metrics.currency)} tone="warning" />
        <Metric label="Net" value={formatMoney(metrics.netTotal, metrics.currency)} tone="muted" />
      </div>

      <div className="records-layout">
        <div className="records-workbench">
          <RecordsFiltersPanel
            counterparties={counterparties}
            filters={filters}
            onChange={onFiltersChange}
          />

          <RecordsTable
            archivingDocumentId={archiveMutation.isPending ? archiveMutation.variables?.documentId ?? null : null}
            isLoading={isLoading}
            onArchive={(record) => archiveMutation.mutate(record)}
            onSelect={setSelectedDocumentId}
            records={records}
            selectedDocumentId={selectedDocumentId}
          />
        </div>
        <div className="records-side-stack">
          <ManualRecordPanel
            canCreate={canCreate}
            client={client}
            counterparties={counterparties}
            onSaved={onRefresh}
          />
          <ReviewColumn
            client={client}
            counterparties={counterparties}
            selectedDocumentId={selectedDocumentId}
            onClose={() => setSelectedDocumentId(null)}
            onSaved={onRefresh}
          />
        </div>
      </div>
    </section>
  );
}

function AiIntakeProGate() {
  const managementUrl = getAutonomoAccountManagementUrl("/apps/autonomoav")
    ?? getAutonomoAccountManagementUrl()
    ?? autonomoProductConfig.links.suite?.href;

  return (
    <section className="intake-page">
      <AiIntakeBridgePanel />
      <Card className="app-card pro-gate-panel" aria-labelledby="ai-pro-gate-title">
        <CardHeader className="flex-row flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle id="ai-pro-gate-title">AI intake is Pro</CardTitle>
            <CardDescription>
              Free workspaces keep manual records without aggressive caps. Pro adds the shared AI queue for web, iPhone, and macOS.
            </CardDescription>
          </div>
          <Badge tone="warning">Upgrade</Badge>
        </CardHeader>
        <CardFooter>
          {managementUrl ? (
            <a className="primary-button" href={managementUrl}>
              Manage Pro
            </a>
          ) : null}
          <a className="secondary-button" href="/">
            Back to records
          </a>
        </CardFooter>
      </Card>
    </section>
  );
}

function AiIntakeBridgePanel() {
  return (
    <Card className="app-card ai-intake-bridge" aria-labelledby="ai-intake-bridge-title">
      <CardHeader className="flex-row flex-wrap items-start justify-between gap-3">
        <div>
          <CardTitle id="ai-intake-bridge-title">One Pro AI inbox across every surface</CardTitle>
          <CardDescription>
            Web, iPhone, and macOS all feed the same backend queue. AI creates drafts only; reviewed records stay human-owned.
          </CardDescription>
        </div>
        <Badge tone="info">Pro</Badge>
      </CardHeader>
      <CardContent>
        <div className="ai-channel-grid">
          <IntakeChannelCard icon={<UploadCloud />} title="Web" detail="Drop PDFs and images from the browser." />
          <IntakeChannelCard icon={<Inbox />} title="iPhone" detail="Share invoices or import files into Autonomo AV Inbox." />
          <IntakeChannelCard icon={<FileText />} title="macOS" detail="Use Finder, Services, drag/drop, and the menu bar app." />
        </div>
      </CardContent>
    </Card>
  );
}

function IntakeChannelCard({ detail, icon, title }: { detail: string; icon: ReactNode; title: string }) {
  return (
    <div className="ai-channel">
      <div className="ai-channel-icon" aria-hidden="true">{icon}</div>
      <div>
        <div className="ai-channel-title">{title}</div>
        <div className="ai-channel-detail">{detail}</div>
      </div>
    </div>
  );
}

function ManualRecordPanel({
  canCreate,
  client,
  counterparties,
  onSaved
}: {
  canCreate: boolean;
  client: AutonomoApiClient;
  counterparties: AutonomoCounterpartySummary[];
  onSaved: () => Promise<void>;
}) {
  const [form, setForm] = useState<ManualRecordFormState>(emptyManualRecordForm);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);

  const mutation = useMutation<AutonomoDocumentDetailResponse, Error, void>({
    mutationFn: async () => {
      if (!canCreate) throw new Error("Complete the business profile before creating records.");
      if (!selectedFile) throw new Error("Attach the invoice, ticket, receipt, or sale file for this V1 record.");
      const validationError = validateManualRecordForm(form);
      if (validationError) throw new Error(validationError);

      let counterpartyId = optionalText(form.counterpartyId);
      const newCounterpartyName = optionalText(form.newCounterpartyName);
      if (!counterpartyId && newCounterpartyName) {
        const created = await client.createCounterparty({
          kind: form.direction === "sale" ? "customer" : "supplier",
          displayName: newCounterpartyName,
          taxId: null,
          vatId: null,
          country: "ES",
          notes: null
        });
        counterpartyId = created.counterparty.counterpartyId;
      }

      return client.createManualRecordWithFile(selectedFile, manualRecordPayloadFromForm(form, selectedFile, counterpartyId));
    },
    onSuccess: async (detail: AutonomoDocumentDetailResponse) => {
      toast.success("Record saved", { description: detail.document.title ?? detail.document.originalFilename });
      setForm(emptyManualRecordForm);
      setSelectedFile(null);
      if (inputRef.current) inputRef.current.value = "";
      await onSaved();
    },
    onError: (error: Error) => toast.error("Record could not be saved", { description: error.message })
  });

  return (
    <Card className="app-card manual-record-panel" aria-labelledby="manual-record-title">
      <CardHeader className="flex-row flex-wrap items-start justify-between gap-3">
        <div>
          <CardTitle id="manual-record-title">Manual record</CardTitle>
          <CardDescription>Enter a purchase, expense, or sale yourself and attach the source document.</CardDescription>
        </div>
        <Badge tone={canCreate ? "success" : "warning"}>{canCreate ? "Ready" : "Profile required"}</Badge>
      </CardHeader>
      <CardContent className="grid gap-4">
        <div className="manual-record-grid">
          <InputField label="Title" value={form.title} placeholder="Invoice 2026-001" onChange={(value) => setForm({ ...form, title: value })} />
          <SelectField label="Kind" value={form.direction} onChange={(value) => setForm({ ...form, direction: value as ManualRecordFormState["direction"] })}>
            <option value="purchase">Purchase / expense</option>
            <option value="sale">Sale</option>
          </SelectField>
          <SelectField label="Type" value={form.documentType} onChange={(value) => setForm({ ...form, documentType: value as AutonomoReviewedDocumentType })}>
            {reviewedDocumentTypes.map((type) => <option key={type} value={type}>{labelFor(type)}</option>)}
          </SelectField>
          <InputField label="Date" type="date" value={form.recordDate} onChange={(value) => setForm({ ...form, recordDate: value, quarter: value ? quarterForDate(value) : form.quarter })} />
          <InputField label="Quarter" value={form.quarter} onChange={(value) => setForm({ ...form, quarter: value })} />
          <SelectField label="Counterparty" value={form.counterpartyId} onChange={(value) => setForm({ ...form, counterpartyId: value })}>
            <option value="">None / create below</option>
            {counterparties.map((counterparty) => <option key={counterparty.counterpartyId} value={counterparty.counterpartyId}>{counterparty.displayName}</option>)}
          </SelectField>
          <InputField label="New counterparty" value={form.newCounterpartyName} placeholder="Supplier or customer name" onChange={(value) => setForm({ ...form, newCounterpartyName: value })} />
          <InputField label="Currency" value={form.currency} onChange={(value) => setForm({ ...form, currency: value.toUpperCase() })} />
          <InputField label="Base" value={form.baseAmount} onChange={(value) => setForm({ ...form, baseAmount: value })} />
          <InputField label="VAT" value={form.vatAmount} onChange={(value) => setForm({ ...form, vatAmount: value })} />
          <InputField label="Total" value={form.totalAmount} onChange={(value) => setForm({ ...form, totalAmount: value })} />
          <InputField label="Category" value={form.category} placeholder="Office rent, software, sales" onChange={(value) => setForm({ ...form, category: value })} />
        </div>
        <TextAreaField label="Notes" value={form.notes} onChange={(value) => setForm({ ...form, notes: value })} />
        <div className="manual-file-row">
          <input
            ref={inputRef}
            className="sr-only"
            type="file"
            accept={uploadAccept}
            onChange={(event) => setSelectedFile(event.target.files?.[0] ?? null)}
          />
          <Button variant="outline" type="button" disabled={!canCreate} onClick={() => inputRef.current?.click()}>
            <FileText />
            Choose source file
          </Button>
          <span className="text-sm text-muted-foreground">
            {selectedFile ? `${selectedFile.name} · ${formatBytes(selectedFile.size)}` : "A file is required in V1."}
          </span>
        </div>
      </CardContent>
      <CardFooter>
        <Button type="button" disabled={!canCreate || mutation.isPending} onClick={() => mutation.mutate()}>
          {mutation.isPending ? <Loader2 className="animate-spin" /> : <CheckCircle2 />}
          Save reviewed record
        </Button>
      </CardFooter>
    </Card>
  );
}

function RecordsFiltersPanel({
  counterparties,
  filters,
  onChange
}: {
  counterparties: AutonomoCounterpartySummary[];
  filters: RecordFiltersState;
  onChange: (filters: RecordFiltersState) => void;
}) {
  const update = <K extends keyof RecordFiltersState>(key: K, value: RecordFiltersState[K]) => onChange({ ...filters, [key]: value });

  return (
    <Card className="app-card records-filters-panel" aria-labelledby="record-filters-title">
      <CardHeader className="flex-row items-center justify-between gap-3">
        <div>
          <CardTitle id="record-filters-title">Period and filters</CardTitle>
          <CardDescription>{recordPeriodDescription(filters)}</CardDescription>
        </div>
        <Filter className="text-muted-foreground" aria-hidden="true" />
      </CardHeader>
      <CardContent>
        <div className="records-filter-grid">
          <SelectField label="Period" value={filters.periodMode} onChange={(value) => update("periodMode", value as RecordsPeriodMode)}>
            <option value="month">Month</option>
            <option value="quarter">Quarter</option>
            <option value="year">Year</option>
            <option value="custom">Custom range</option>
          </SelectField>
          {filters.periodMode === "month" ? (
            <InputField label="Month" type="month" value={filters.month} onChange={(value) => update("month", value)} />
          ) : null}
          {filters.periodMode === "quarter" ? (
            <InputField label="Quarter" value={filters.quarter} placeholder="2026-Q2" onChange={(value) => update("quarter", value)} />
          ) : null}
          {filters.periodMode === "year" ? (
            <InputField label="Year" type="number" value={filters.year} onChange={(value) => update("year", value)} />
          ) : null}
          {filters.periodMode === "custom" ? (
            <>
              <InputField label="From" type="date" value={filters.dateFrom} onChange={(value) => update("dateFrom", value)} />
              <InputField label="To" type="date" value={filters.dateTo} onChange={(value) => update("dateTo", value)} />
            </>
          ) : null}
          <SelectField label="Records" value={filters.kind} onChange={(value) => update("kind", value as RecordKindFilter)}>
            <option value="all">All records</option>
            <option value="sales">Sales</option>
            <option value="purchases">Purchases</option>
            <option value="expenses">Expenses</option>
          </SelectField>
          <SelectField label="Counterparty" value={filters.counterpartyId} onChange={(value) => update("counterpartyId", value)}>
            <option value="all">All counterparties</option>
            {counterparties.map((counterparty) => <option key={counterparty.counterpartyId} value={counterparty.counterpartyId}>{counterparty.displayName}</option>)}
          </SelectField>
          <InputField label="Category" value={filters.category} placeholder="Exact category" onChange={(value) => update("category", value)} />
          <InputField label="Limit" type="number" value={String(filters.limit)} onChange={(value) => update("limit", clampRecordLimit(value))} />
        </div>
      </CardContent>
    </Card>
  );
}

function RecordsTable({
  archivingDocumentId,
  isLoading,
  onArchive,
  onSelect,
  records,
  selectedDocumentId
}: {
  archivingDocumentId: string | null;
  isLoading: boolean;
  onArchive: (record: AutonomoRecordListItem) => void;
  onSelect: (documentId: string) => void;
  records: AutonomoRecordListItem[];
  selectedDocumentId: string | null;
}) {
  return (
    <Card className="app-card records-table-panel" aria-labelledby="records-table-title">
      <CardHeader className="flex-row flex-wrap items-center justify-between gap-3">
        <div>
          <CardTitle id="records-table-title">Records</CardTitle>
          <CardDescription>Reviewed sales, purchases, expenses, tickets, receipts, and attached source files.</CardDescription>
        </div>
        {isLoading ? <Badge tone="muted">Loading</Badge> : <Badge tone="info">{records.length} rows</Badge>}
      </CardHeader>
      <CardContent>
        <div className="document-table-wrap">
          <table className="document-table records-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Record</th>
                <th>Counterparty</th>
                <th>Category</th>
                <th>Base</th>
                <th>VAT</th>
                <th>Total</th>
                <th>Source file</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {records.length === 0 ? (
                <tr>
                  <td colSpan={9}>
                    <div className="empty-table">
                      <Search className="size-5" aria-hidden="true" />
                      No reviewed records match this period.
                    </div>
                  </td>
                </tr>
              ) : (
                records.map((record) => (
                  <tr
                    key={record.recordId}
                    className={record.documentId === selectedDocumentId ? "selected-row" : undefined}
                  >
                    <td>{formatDate(record.recordDate)}</td>
                    <td>
                      <div className="cell-title">{record.documentTitle ?? labelFor(record.documentType)}</div>
                      <div className="cell-subtitle">{labelFor(record.direction)} · {labelFor(record.documentType)} · {record.quarter}</div>
                    </td>
                    <td>{record.counterpartyDisplayName ?? "Not set"}</td>
                    <td>{record.category ?? "Not set"}</td>
                    <td>{formatMoney(record.baseAmount, record.currency)}</td>
                    <td>{formatMoney(record.vatAmount, record.currency)}</td>
                    <td><strong>{formatMoney(record.totalAmount, record.currency)}</strong></td>
                    <td>
                      <div className="cell-title">{record.originalFilename}</div>
                      <div className="cell-subtitle">{labelFor(record.source)} · {formatBytes(record.byteSize)}</div>
                    </td>
                    <td>
                      <div className="table-actions">
                        <Button variant="outline" size="sm" type="button" onClick={() => onSelect(record.documentId)}>
                          Edit
                        </Button>
                        <Button
                          variant="outline"
                          size="icon"
                          type="button"
                          aria-label={`Archive ${record.documentTitle ?? record.originalFilename}`}
                          disabled={archivingDocumentId === record.documentId}
                          onClick={() => onArchive(record)}
                        >
                          {archivingDocumentId === record.documentId ? <Loader2 className="animate-spin" /> : <Trash2 />}
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
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
    <Card className="app-card business-profile-panel" aria-labelledby="business-profile-title">
      <CardHeader className="flex-row items-start justify-between gap-3">
        <div>
          <CardTitle id="business-profile-title">{title}</CardTitle>
          <CardDescription>Only type, legal name, and country are required to start creating records.</CardDescription>
        </div>
        <Badge tone={complete ? "success" : "warning"}>{complete ? "Ready" : "Required"}</Badge>
      </CardHeader>
      <CardContent className="grid gap-4">
      <div className="onboarding-minimal-grid">
        <SelectField label="Type" value={form.kind} onChange={(value) => setForm({ ...form, kind: value as AutonomoBusinessProfileKind })}>
          {businessProfileKinds.map((kind) => <option key={kind} value={kind}>{labelFor(kind)}</option>)}
        </SelectField>
        <InputField label="Legal name" value={form.legalName} onChange={(value) => setForm({ ...form, legalName: value })} />
        <InputField label="Tax / VAT ID (optional)" value={form.taxId} onChange={(value) => setForm({ ...form, taxId: value })} />
        <InputField label="Country" value={form.country} placeholder="ES" onChange={(value) => setForm({ ...form, country: value.toUpperCase() })} />
      </div>
      <p className="section-copy">Optional trade name, VAT split, and fiscal address can be added later in settings when they become necessary.</p>
      </CardContent>
      <CardFooter>
        <Button type="button" disabled={saveMutation.isPending} onClick={save}>
          {saveMutation.isPending ? <Loader2 className="animate-spin" /> : <CheckCircle2 />}
          Save profile
        </Button>
        {profile?.updatedAt ? <span className="text-sm text-muted-foreground">Updated {formatDate(profile.updatedAt)}</span> : null}
      </CardFooter>
    </Card>
  );
}

function UploadPanel({ canUpload, client, onUploaded }: { canUpload: boolean; client: AutonomoApiClient; onUploaded: () => Promise<void> }) {
  const [dragActive, setDragActive] = useState(false);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const uploadMutation = useMutation<AutonomoUploadCompletionResponse, Error, File>({
    mutationFn: (file: File) => client.uploadFile(file),
    onSuccess: async (response: AutonomoUploadCompletionResponse) => {
      if (response.documentStatus === "duplicate") {
        toast.info("Duplicate document detected", {
          description: `${response.documentId} matches an existing workspace document and was not queued again.`
        });
      } else {
        toast.success("Document queued", {
          description: `${response.documentId} is ready for Autonomo AV processing.`
        });
      }
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
    <Card className="app-card upload-panel" aria-labelledby="upload-title">
      <CardHeader>
        <CardTitle id="upload-title">Send to AI inbox</CardTitle>
        <CardDescription>
          {canUpload
            ? "Drop one PDF or image here. It joins the same Pro queue used by iPhone and macOS intake."
            : "Complete the minimum fiscal setup before sending documents to AI."}
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-4">
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
        <div className="drop-zone-icon" aria-hidden="true">
          <UploadCloud />
        </div>
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
        <Button variant="outline" type="button" disabled={!canUpload} onClick={() => inputRef.current?.click()}>
          <FileText />
          Choose file
        </Button>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {selectedFile ? (
          <span className="text-sm text-muted-foreground">
            {selectedFile.name} · {formatBytes(selectedFile.size)}
          </span>
        ) : (
          <span className="text-sm text-muted-foreground">No file selected.</span>
        )}
        <Button
          type="button"
          disabled={!canUpload || !selectedFile || uploadMutation.isPending}
          onClick={() => selectedFile ? uploadMutation.mutate(selectedFile) : undefined}
        >
          {uploadMutation.isPending ? <Loader2 className="animate-spin" /> : <UploadCloud />}
          Upload
        </Button>
      </div>
      </CardContent>
    </Card>
  );
}

function DocumentList({
  actionLabel = "Review",
  description = "Open a row to review the draft and accepted record.",
  documents,
  emptyMessage = "No documents match the current filters.",
  isLoading,
  onSelect,
  selectedDocumentId,
  title = "Inbox"
}: {
  actionLabel?: string;
  description?: string;
  documents: AutonomoDocumentListItem[];
  emptyMessage?: string;
  isLoading: boolean;
  onSelect: (documentId: string) => void;
  selectedDocumentId: string | null;
  title?: string;
}) {
  return (
    <Card className="app-card document-list-panel" aria-labelledby="document-list-title">
      <CardHeader className="flex-row flex-wrap items-center justify-between gap-3">
        <div>
          <CardTitle id="document-list-title">{title}</CardTitle>
          <CardDescription>{description}</CardDescription>
        </div>
        {isLoading ? <Badge tone="muted">Loading</Badge> : <Badge tone="info">{documents.length} shown</Badge>}
      </CardHeader>
      <CardContent>
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
                    {emptyMessage}
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
                      <Button variant="outline" size="sm" type="button" onClick={() => onSelect(document.documentId)}>
                        <FileText aria-hidden="true" />
                        {actionLabel}
                      </Button>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
      </CardContent>
    </Card>
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
        <Button variant="ghost" size="icon" type="button" onClick={onClose} aria-label="Close document review">
          <X />
        </Button>
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
            <Button variant="outline" type="button" onClick={() => fileMutation.mutate()} disabled={fileMutation.isPending}>
              {fileMutation.isPending ? <Loader2 className="animate-spin" /> : <ArrowDownToLine />}
              Preview file
            </Button>
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
            <Button type="button" disabled={saveMutation.isPending} onClick={() => saveWithStatus("reviewed")}>
              {saveMutation.isPending ? <Loader2 className="animate-spin" /> : <CheckCircle2 />}
              Save reviewed
            </Button>
            <Button variant="outline" type="button" disabled={saveMutation.isPending} onClick={() => saveWithStatus("queued")}>
              <RotateCcw />
              Ask reprocess
            </Button>
            <Button variant="outline" type="button" disabled={saveMutation.isPending} onClick={() => saveWithStatus("duplicate")}>
              Mark duplicate
            </Button>
            <Button variant="outline" type="button" disabled={saveMutation.isPending} onClick={() => saveWithStatus("ignored")}>
              Ignore
            </Button>
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
          <Button variant="outline" type="button" onClick={onApply}>
            Apply draft fields
          </Button>
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
      <Button className="w-fit" variant="outline" type="button" disabled={isCreating || form.displayName.trim().length === 0} onClick={onCreate}>
        {isCreating ? <Loader2 className="animate-spin" /> : <Plus />}
        Create and select
      </Button>
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
            <Button
              variant="outline"
              size="icon"
              type="button"
              aria-label="Copy private email alias"
              onClick={() => {
                if (emailIntake.alias) {
                  void navigator.clipboard.writeText(emailIntake.alias);
                  toast.success("Alias copied");
                }
              }}
            >
              <Copy />
            </Button>
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
    <Card className={`metric metric-${tone}`}>
      <div className="metric-label">{label}</div>
      <div className="metric-value">{value}</div>
    </Card>
  );
}

function SummaryTile({ detail, label, value }: { detail: string; label: string; value: string }) {
  return (
    <Card className="summary-tile">
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </Card>
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
  return (
    <UiBadge
      className={cn("tone-badge", `tone-badge-${tone}`)}
      variant={tone === "danger" ? "destructive" : tone === "muted" ? "secondary" : "outline"}
    >
      {children}
    </UiBadge>
  );
}

function InlineAlert({ children, title, tone = "muted" }: { children: ReactNode; title: string; tone?: "danger" | "muted" | "warning" }) {
  return (
    <Alert className={cn("inline-alert", `inline-alert-${tone}`)} variant={tone === "danger" ? "destructive" : "default"}>
      <AlertTriangle aria-hidden="true" />
      <div>
        <AlertTitle>{title}</AlertTitle>
        <AlertDescription>{children}</AlertDescription>
      </div>
    </Alert>
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
      <Input type={type} value={value} placeholder={placeholder} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}

function TextAreaField({ label, onChange, value }: { label: string; onChange: (value: string) => void; value: string }) {
  return (
    <label className="field-label field-wide">
      <span>{label}</span>
      <Textarea value={value} rows={3} onChange={(event) => onChange(event.target.value)} />
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
  if (path.startsWith("/intake")) return "intake";
  if (path.startsWith("/ledger") || path.startsWith("/records")) return "records";
  if (path.startsWith("/quarter")) return "quarter";
  if (path.startsWith("/settings")) return "settings";
  return "records";
}

function pathForRoute(route: AppRoute) {
  if (route === "sign-in") return "/sign-in";
  if (route === "delete-account") return "/delete-account";
  if (route === "privacy") return "/privacy";
  if (route === "support") return "/support";
  if (route === "terms") return "/terms";
  if (route === "records") return "/";
  if (route === "intake") return "/intake";
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

function todayDateOnly() {
  return new Date().toISOString().slice(0, 10);
}

function currentMonth() {
  return todayDateOnly().slice(0, 7);
}

function currentYear() {
  return todayDateOnly().slice(0, 4);
}

function defaultRecordFilters(): RecordFiltersState {
  return {
    periodMode: "year",
    month: currentMonth(),
    quarter: currentQuarter(),
    year: currentYear(),
    dateFrom: `${currentYear()}-01-01`,
    dateTo: todayDateOnly(),
    kind: "all",
    counterpartyId: "all",
    category: "",
    limit: 100
  };
}

function recordListQueryFromFilters(filters: RecordFiltersState): AutonomoRecordListQuery {
  const period = recordPeriodRange(filters);
  return {
    ...period,
    direction: filters.kind === "sales" ? "sale" : filters.kind === "purchases" || filters.kind === "expenses" ? "purchase" : undefined,
    counterpartyId: filters.counterpartyId === "all" ? undefined : filters.counterpartyId,
    category: filterText(filters.category),
    limit: filters.limit
  };
}

function recordPeriodRange(filters: RecordFiltersState): Pick<AutonomoRecordListQuery, "dateFrom" | "dateTo" | "quarter"> {
  if (filters.periodMode === "quarter") {
    return { quarter: filterText(filters.quarter) };
  }

  if (filters.periodMode === "month") {
    const match = /^(\d{4})-(\d{2})$/.exec(filters.month);
    if (!match) return {};
    const year = Number(match[1]);
    const month = Number(match[2]);
    if (month < 1 || month > 12) return {};
    const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
    return {
      dateFrom: `${filters.month}-01`,
      dateTo: `${filters.month}-${String(lastDay).padStart(2, "0")}`
    };
  }

  if (filters.periodMode === "custom") {
    return {
      dateFrom: filterText(filters.dateFrom),
      dateTo: filterText(filters.dateTo)
    };
  }

  const year = /^\d{4}$/.test(filters.year) ? filters.year : currentYear();
  return {
    dateFrom: `${year}-01-01`,
    dateTo: `${year}-12-31`
  };
}

function recordPeriodDescription(filters: RecordFiltersState) {
  if (filters.periodMode === "month") return `Showing reviewed records for ${filters.month || "a selected month"}.`;
  if (filters.periodMode === "quarter") return `Showing reviewed records for ${filters.quarter || "a selected quarter"}.`;
  if (filters.periodMode === "custom") return "Showing reviewed records in the selected custom range.";
  return `Showing reviewed records for ${filters.year || currentYear()}.`;
}

function filterRecordsByKind(records: AutonomoRecordListItem[], kind: RecordKindFilter) {
  if (kind === "expenses") {
    return records.filter((record) => record.direction === "purchase" && (record.documentType === "ticket" || record.documentType === "receipt"));
  }
  return records;
}

function manualRecordPayloadFromForm(
  form: ManualRecordFormState,
  file: File,
  counterpartyId: string | null
): AutonomoDocumentManualReviewRequest {
  const title = optionalText(form.title) ?? file.name.replace(/\.[^.]+$/, "");
  return {
    status: "reviewed",
    title,
    direction: form.direction,
    documentType: form.documentType,
    documentDate: form.recordDate,
    quarter: form.quarter,
    counterpartyId,
    reviewedRecord: {
      counterpartyId,
      direction: form.direction,
      documentType: form.documentType,
      recordDate: form.recordDate,
      quarter: form.quarter,
      currency: form.currency.toUpperCase(),
      baseAmount: form.baseAmount,
      vatAmount: form.vatAmount,
      totalAmount: form.totalAmount,
      category: optionalText(form.category),
      notes: optionalText(form.notes)
    }
  };
}

function archivePayloadFromRecord(record: AutonomoRecordListItem): AutonomoDocumentManualReviewRequest {
  return {
    status: "ignored",
    title: record.documentTitle,
    direction: record.direction,
    documentType: record.documentType,
    documentDate: record.recordDate,
    quarter: record.quarter,
    counterpartyId: record.counterpartyId,
    reviewedRecord: null
  };
}

function validateManualRecordForm(form: ManualRecordFormState) {
  if (!form.recordDate) return "Record date is required.";
  if (!form.quarter) return "Quarter is required.";
  if (quarterForDate(form.recordDate) !== form.quarter) return "Quarter must match the record date.";
  if (!/^[A-Z]{3}$/.test(form.currency)) return "Currency must be a 3-letter ISO code.";
  if (!isValidMoney(form.baseAmount) || !isValidMoney(form.vatAmount) || !isValidMoney(form.totalAmount)) {
    return "Base, VAT, and total must be non-negative amounts with up to 2 decimals.";
  }
  return null;
}

function recordMetricsFromRecords(records: AutonomoRecordListItem[]) {
  const currency = records[0]?.currency ?? "EUR";
  let salesTotal = 0;
  let purchaseTotal = 0;
  let vatTotal = 0;

  for (const record of records) {
    const total = Number(record.totalAmount);
    const vat = Number(record.vatAmount);
    if (record.direction === "sale" && Number.isFinite(total)) salesTotal += total;
    if (record.direction === "purchase" && Number.isFinite(total)) purchaseTotal += total;
    if (Number.isFinite(vat)) vatTotal += vat;
  }

  return {
    currency,
    salesTotal: moneyString(salesTotal),
    purchaseTotal: moneyString(purchaseTotal),
    vatTotal: moneyString(vatTotal),
    netTotal: moneyString(salesTotal - purchaseTotal)
  };
}

function metricsFromDocuments(documents: AutonomoDocumentListItem[]) {
  return {
    drafted: documents.filter((document) => document.status === "drafted").length,
    failed: documents.filter((document) => document.status === "failed" || document.status === "quarantined").length,
    needsReview: documents.filter((document) => document.status === "needs_review").length,
    queued: documents.filter((document) => document.status === "queued" || document.status === "uploaded" || document.status === "processing").length
  };
}

function isOperationalDocument(document: AutonomoDocumentListItem) {
  if (document.intakeMode !== "ai_intake") return false;
  return (
    document.status === "queued"
    || document.status === "uploaded"
    || document.status === "processing"
    || document.status === "drafted"
    || document.status === "needs_review"
    || document.status === "failed"
    || document.status === "quarantined"
  );
}

function businessProfileFormFromProfile(profile: AutonomoWorkspaceBusinessProfile | null) {
  return {
    kind: profile?.kind ?? ("self_employed" as AutonomoBusinessProfileKind),
    legalName: profile?.legalName ?? "",
    tradeName: profile?.tradeName ?? "",
    taxId: profile?.taxId ?? profile?.vatId ?? "",
    vatId: profile?.vatId ?? "",
    country: profile?.country ?? "ES",
    fiscalAddress: profile?.fiscalAddress ?? ""
  };
}

function validateBusinessProfileForm(form: ReturnType<typeof businessProfileFormFromProfile>) {
  if (!form.legalName.trim()) return "Legal name is required.";
  if (!/^[A-Z]{2}$/.test(form.country.trim().toUpperCase())) return "Country must be a two-letter code such as ES.";
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

function clampRecordLimit(value: string) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 100;
  return Math.min(Math.max(Math.trunc(parsed), 1), 250);
}
