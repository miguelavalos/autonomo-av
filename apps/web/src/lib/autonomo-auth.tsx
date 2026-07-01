import {
  AccountAvProvider,
  AccountSignIn,
  useAccountSession,
  useAccountToken,
  type AccountAvAppId
} from "@avalsys/account-av-web/client";
import { createContext, useContext, useMemo, type ReactNode } from "react";
import {
  getAutonomoAccountApiBaseUrl,
  getAutonomoAccountPublishableKey,
  getAutonomoDevToken
} from "@/lib/autonomo-config";

export type AutonomoAuthMode = "account-av" | "dev-bearer" | "fixture" | "missing-config";

export interface AutonomoAuthSession {
  authMode: AutonomoAuthMode;
  getToken: () => Promise<string | null>;
  isLoaded: boolean;
  isSignedIn: boolean;
  sessionId: string | null;
  statusLabel: string;
  userId: string | null;
}

interface AutonomoAuthProviderProps {
  children: ReactNode;
  useFixtures: boolean;
}

const AutonomoAuthContext = createContext<AutonomoAuthSession | null>(null);
const signInPath = "/sign-in";
const autonomoAccountAppId = "autonomoav" as AccountAvAppId;

export function AutonomoAuthProvider({ children, useFixtures }: AutonomoAuthProviderProps) {
  const accountApiBaseUrl = getAutonomoAccountApiBaseUrl();
  const publishableKey = getAutonomoAccountPublishableKey();
  const devToken = getAutonomoDevToken()?.trim() || null;

  if (useFixtures) {
    return (
      <AutonomoAuthContext.Provider value={fixtureAuthSession}>
        {children}
      </AutonomoAuthContext.Provider>
    );
  }

  if (accountApiBaseUrl && publishableKey) {
    return (
      <AccountAvProvider
        accountApiBaseUrl={accountApiBaseUrl}
        afterSignOutUrl={signInPath}
        appDisplayName="Autonomo AV"
        appId={autonomoAccountAppId}
        publishableKey={publishableKey}
        signInUrl={signInPath}
        signUpUrl={signInPath}
      >
        <AccountAuthBridge>{children}</AccountAuthBridge>
      </AccountAvProvider>
    );
  }

  if (devToken) {
    return (
      <AutonomoAuthContext.Provider value={devBearerAuthSession(devToken)}>
        {children}
      </AutonomoAuthContext.Provider>
    );
  }

  return (
    <AutonomoAuthContext.Provider value={missingConfigAuthSession}>
      {children}
    </AutonomoAuthContext.Provider>
  );
}

export function useAutonomoAuthSession() {
  const context = useContext(AutonomoAuthContext);
  if (!context) {
    throw new Error("useAutonomoAuthSession must be used inside AutonomoAuthProvider.");
  }
  return context;
}

export function AutonomoAccountSignIn({ fallbackRedirectUrl }: { fallbackRedirectUrl: string }) {
  const auth = useAutonomoAuthSession();
  if (auth.authMode !== "account-av") {
    return null;
  }
  return <AccountSignIn fallbackRedirectUrl={fallbackRedirectUrl} path={signInPath} signUpUrl={signInPath} />;
}

function AccountAuthBridge({ children }: { children: ReactNode }) {
  const accountSession = useAccountSession();
  const getAccountToken = useAccountToken();
  const value = useMemo<AutonomoAuthSession>(
    () => ({
      authMode: "account-av",
      getToken: async () => accountSession.isSignedIn ? getAccountToken() : null,
      isLoaded: accountSession.isLoaded,
      isSignedIn: Boolean(accountSession.isSignedIn),
      sessionId: accountSession.sessionId ?? null,
      statusLabel: "Account AV",
      userId: accountSession.userId ?? null
    }),
    [accountSession.isLoaded, accountSession.isSignedIn, accountSession.sessionId, accountSession.userId, getAccountToken]
  );

  return <AutonomoAuthContext.Provider value={value}>{children}</AutonomoAuthContext.Provider>;
}

const fixtureAuthSession: AutonomoAuthSession = {
  authMode: "fixture",
  getToken: async () => null,
  isLoaded: true,
  isSignedIn: true,
  sessionId: "fixture",
  statusLabel: "Fixture",
  userId: "fixture-user"
};

function devBearerAuthSession(token: string): AutonomoAuthSession {
  return {
    authMode: "dev-bearer",
    getToken: async () => token,
    isLoaded: true,
    isSignedIn: true,
    sessionId: "dev-bearer",
    statusLabel: "Dev token",
    userId: "dev-bearer-user"
  };
}

const missingConfigAuthSession: AutonomoAuthSession = {
  authMode: "missing-config",
  getToken: async () => null,
  isLoaded: true,
  isSignedIn: false,
  sessionId: null,
  statusLabel: "Auth missing",
  userId: null
};
