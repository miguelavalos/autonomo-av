import type { AppsAvProductConfig, AppsAvProductLink } from "@avalsys/apps-av-web";
import type { AutonomoEmailIntakeSettings } from "@/lib/autonomo-types";

export const autonomoAccent = "#2F9E83";

export const autonomoProductConfig: AppsAvProductConfig = {
  appId: "autonomoav",
  accentColor: autonomoAccent,
  name: "Autonomo AV",
  links: {
    deleteAccount: externalLink(import.meta.env.VITE_AUTONOMOAV_DELETE_ACCOUNT_URL || commercialSiteUrl("/delete-account"), "Delete account"),
    privacy: externalLink(import.meta.env.VITE_AUTONOMOAV_PRIVACY_URL || commercialSiteUrl("/privacy"), "Privacy"),
    suite: externalLink(import.meta.env.VITE_ACCOUNTAV_MANAGEMENT_URL, "Apps"),
    support: externalLink(supportUrl(), "Support"),
    terms: externalLink(import.meta.env.VITE_AUTONOMOAV_TERMS_URL || commercialSiteUrl("/terms"), "Terms")
  }
};

export const autonomoNavLinks: AppsAvProductLink[] = [
  { href: "/", label: "Inbox" },
  { href: "/quarter", label: "Quarter" },
  { href: "/settings", label: "Settings" }
];

export const autonomoFooterLabels = {
  deleteAccount: "Delete account",
  language: "Language",
  privacy: "Privacy",
  support: "Support",
  terms: "Terms",
  website: "Website"
};

export const autonomoShellLabels = {
  home: "Autonomo AV inbox",
  mobileNavigation: "Mobile navigation",
  openNavigation: "Open navigation",
  primaryNavigation: "Primary navigation"
};

export function getAutonomoApiBaseUrl() {
  return trimTrailingSlash(import.meta.env.VITE_AUTONOMOAV_API_BASE_URL);
}

export function getAutonomoDevToken() {
  return import.meta.env.VITE_AUTONOMOAV_DEV_BEARER_TOKEN as string | undefined;
}

export function getAutonomoAccountApiBaseUrl() {
  return trimTrailingSlash(import.meta.env.VITE_ACCOUNTAV_API_BASE_URL);
}

export function getAutonomoAccountPublishableKey() {
  return import.meta.env.VITE_ACCOUNTAV_PUBLISHABLE_KEY as string | undefined;
}

export function useAutonomoFixtures() {
  return import.meta.env.VITE_AUTONOMOAV_USE_FIXTURES !== "false";
}

export function getEmailIntakeSettings(useFixtures: boolean): AutonomoEmailIntakeSettings {
  const enabledFromEnv = import.meta.env.VITE_AUTONOMOAV_EMAIL_INTAKE_ENABLED;
  const enabled = enabledFromEnv === undefined ? useFixtures : enabledFromEnv === "true";
  return {
    enabled,
    alias: enabled
      ? (import.meta.env.VITE_AUTONOMOAV_EMAIL_ALIAS as string | undefined) ?? "marta-rojas@inbox.autonomo-av.avalsys.com"
      : null,
    status: enabled ? "active" : "disabled"
  };
}

function accountManagementUrl(path: string) {
  const baseUrl = trimTrailingSlash(import.meta.env.VITE_ACCOUNTAV_MANAGEMENT_URL);
  return baseUrl ? `${baseUrl}${path}` : undefined;
}

function supportUrl() {
  return trimTrailingSlash(import.meta.env.VITE_SUPPORTAV_BASE_URL) || commercialSiteUrl("/support");
}

function commercialSiteUrl(path: string) {
  const privacyUrl = trimTrailingSlash(import.meta.env.VITE_AUTONOMOAV_PRIVACY_URL);
  const url = privacyUrl ? new URL(privacyUrl) : new URL("https://autonomo-av.avalsys.com");
  return `${url.origin}${path}`;
}

function externalLink(href: string | undefined, label: string) {
  const normalized = normalizeHref(href);
  return normalized ? { href: normalized, label, external: true } : undefined;
}

function normalizeHref(value: string | undefined) {
  if (!value) return "";
  return value.startsWith("mailto:") ? value.trim() : trimTrailingSlash(value);
}

function trimTrailingSlash(value: string | undefined) {
  return value?.trim().replace(/\/+$/, "") ?? "";
}
