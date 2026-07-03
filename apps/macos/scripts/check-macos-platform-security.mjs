#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const macosRoot = dirname(scriptDir);
const infoPlistPath = join(macosRoot, "Supporting/Info.plist");
const entitlementsPath = join(macosRoot, "Supporting/AutonomoAVMac.entitlements");
const shareInfoPlistPath = join(macosRoot, "ShareExtension/Info.plist");
const shareEntitlementsPath = join(macosRoot, "ShareExtension/AutonomoAVMacShareExtension.entitlements");

function readPlist(path) {
  const json = execFileSync("plutil", ["-convert", "json", "-o", "-", path], {
    encoding: "utf8",
  });
  return JSON.parse(json);
}

const failures = [];
const info = readPlist(infoPlistPath);
const entitlements = readPlist(entitlementsPath);
const shareInfo = readPlist(shareInfoPlistPath);
const shareEntitlements = readPlist(shareEntitlementsPath);
const infoSource = readFileSync(infoPlistPath, "utf8");
const shareInfoSource = readFileSync(shareInfoPlistPath, "utf8");

function fail(message) {
  failures.push(message);
}

function requireExactArray(name, value, expected) {
  if (!Array.isArray(value) || value.length !== expected.length) {
    fail(`${name} must contain exactly ${expected.join(", ")}.`);
    return;
  }
  for (const item of expected) {
    if (!value.includes(item)) {
      fail(`${name} is missing ${item}.`);
    }
  }
}

const ats = info.NSAppTransportSecurity ?? {};
if (ats.NSAllowsArbitraryLoads === true) {
  fail("NSAllowsArbitraryLoads must stay disabled; use scoped ATS exceptions only.");
}
if (ats.NSAllowsArbitraryLoadsInWebContent === true) {
  fail("NSAllowsArbitraryLoadsInWebContent must stay disabled for embedded web content.");
}
if (ats.NSAllowsLocalNetworking === true) {
  fail("NSAllowsLocalNetworking must not be enabled in the checked-in Info.plist.");
}
if (ats.NSExceptionDomains && Object.keys(ats.NSExceptionDomains).length > 0) {
  fail("ATS domain exceptions must be reviewed before being checked in.");
}

const allowedAppEntitlementKeys = new Set([
  "com.apple.security.app-sandbox",
  "com.apple.security.application-groups",
  "com.apple.security.files.user-selected.read-only",
  "com.apple.security.network.client",
  "keychain-access-groups",
]);
for (const key of Object.keys(entitlements)) {
  if (!allowedAppEntitlementKeys.has(key)) {
    fail(`unexpected main app entitlement: ${key}`);
  }
}

if (entitlements["com.apple.security.app-sandbox"] !== true) {
  fail("App Sandbox must stay enabled for Mac App Store distribution.");
}
if (entitlements["com.apple.security.network.client"] !== true) {
  fail("Network client entitlement is required for Account AV and Autonomo API calls.");
}
if (entitlements["com.apple.security.files.user-selected.read-only"] !== true) {
  fail("User-selected read-only file access is required for file picker/open-with intake.");
}
requireExactArray(
  "main app application groups",
  entitlements["com.apple.security.application-groups"],
  ["$(AUTONOMOAV_APP_GROUP_IDENTIFIER)"],
);
requireExactArray(
  "main app keychain access groups",
  entitlements["keychain-access-groups"],
  ["$(ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)"],
);

const allowedShareEntitlementKeys = new Set([
  "com.apple.security.app-sandbox",
  "com.apple.security.application-groups",
]);
for (const key of Object.keys(shareEntitlements)) {
  if (!allowedShareEntitlementKeys.has(key)) {
    fail(`unexpected share extension entitlement: ${key}`);
  }
}
if (shareEntitlements["com.apple.security.app-sandbox"] !== true) {
  fail("Share extension App Sandbox must stay enabled.");
}
requireExactArray(
  "share extension application groups",
  shareEntitlements["com.apple.security.application-groups"],
  ["$(AUTONOMOAV_APP_GROUP_IDENTIFIER)"],
);
if (shareEntitlements["keychain-access-groups"]) {
  fail("Share extension must not have keychain access groups.");
}
if (shareEntitlements["com.apple.security.network.client"] === true) {
  fail("Share extension must not have network client entitlement.");
}

const requiredInfoSubstitutions = [
  "$(ACCOUNTAV_API_BASE_URL)",
  "$(ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)",
  "$(ACCOUNTAV_KEYCHAIN_SERVICE)",
  "$(ACCOUNTAV_PUBLISHABLE_KEY)",
  "$(AUTONOMOAV_API_BASE_URL)",
  "$(AUTONOMOAV_APP_GROUP_IDENTIFIER)",
];
for (const token of requiredInfoSubstitutions) {
  if (!infoSource.includes(token)) {
    fail(`main app Info.plist must keep ${token} as a build-setting substitution.`);
  }
}
if (!shareInfoSource.includes("$(AUTONOMOAV_APP_GROUP_IDENTIFIER)")) {
  fail("share extension Info.plist must expose AUTONOMOAV_APP_GROUP_IDENTIFIER as a build-setting substitution.");
}

const expectedContentTypes = [
  "com.adobe.pdf",
  "public.jpeg",
  "public.png",
  "org.webmproject.webp",
  "public.heic",
  "public.heif",
];
const documentTypes = info.CFBundleDocumentTypes ?? [];
const documentContentTypes = documentTypes.flatMap((entry) => entry.LSItemContentTypes ?? []);
requireExactArray("Finder/Open With document types", documentContentTypes, expectedContentTypes);

const services = info.NSServices ?? [];
if (services.length !== 1) {
  fail("main app must register exactly one NSServices entry for file intake.");
} else {
  const service = services[0];
  if (service.NSMessage !== "sendFilesToAutonomoAV") {
    fail("NSServices NSMessage must remain sendFilesToAutonomoAV.");
  }
  if (service.NSPortName !== "Autonomo AV") {
    fail("NSServices NSPortName must remain Autonomo AV.");
  }
  requireExactArray("Services file types", service.NSSendFileTypes ?? [], expectedContentTypes);
}

const extension = shareInfo.NSExtension ?? {};
const extensionAttributes = extension.NSExtensionAttributes ?? {};
const activationRule = extensionAttributes.NSExtensionActivationRule ?? {};
if (extension.NSExtensionPointIdentifier !== "com.apple.share-services") {
  fail("share extension must stay registered for com.apple.share-services.");
}
if (activationRule.NSExtensionActivationSupportsFileWithMaxCount !== 10) {
  fail("share extension must support file activation with max count 10.");
}
if (activationRule.NSExtensionActivationSupportsImageWithMaxCount !== 10) {
  fail("share extension must support image activation with max count 10.");
}
for (const unsupportedKey of [
  "NSExtensionActivationSupportsText",
  "NSExtensionActivationSupportsWebURLWithMaxCount",
]) {
  if (activationRule[unsupportedKey] !== undefined) {
    fail(`share extension must not advertise unsupported activation key ${unsupportedKey}.`);
  }
}

if (info.NSAppleEventsUsageDescription || shareInfo.NSAppleEventsUsageDescription) {
  fail("macOS V1 must not request Apple Events/Automation usage.");
}
if (
  entitlements["com.apple.security.automation.apple-events"] === true ||
  shareEntitlements["com.apple.security.automation.apple-events"] === true
) {
  fail("macOS V1 must not request Apple Events automation entitlement.");
}

if (failures.length > 0) {
  console.error("macOS platform security check failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("macOS platform security check passed.");
