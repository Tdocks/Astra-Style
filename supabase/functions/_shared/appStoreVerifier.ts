/// <reference types="npm:@types/node" />

import { Buffer } from "node:buffer";
import { EdgeAppStoreVerifier } from "./edgeAppStoreVerifier.ts";
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "npm:@apple/app-store-server-library@3.1.0";

export class AppStoreVerificationError extends Error {
  readonly retryable: boolean;

  constructor(retryable: boolean, cause: unknown) {
    super("App Store signed data could not be verified.", { cause });
    this.retryable = retryable;
  }
}

export class AppStoreConfigurationError extends Error {}

export type AppStoreEnvironment = "sandbox" | "production";

export interface VerifiedTransaction {
  readonly originalTransactionId?: string;
  readonly transactionId?: string;
  readonly productId?: string;
  readonly purchaseDate?: number;
  readonly expiresDate?: number;
  readonly signedDate?: number;
  readonly appAccountToken?: string;
  readonly revocationDate?: number;
  readonly isUpgraded?: boolean;
  readonly environment?: string;
  readonly bundleId?: string;
}

export interface VerifiedRenewalInfo {
  readonly gracePeriodExpiresDate?: number;
}

export interface VerifiedNotification {
  readonly notificationUUID?: string;
  readonly notificationType?: string;
  readonly subtype?: string;
  readonly signedDate?: number;
  readonly data?: {
    readonly environment?: string;
    readonly bundleId?: string;
    readonly signedTransactionInfo?: string;
    readonly signedRenewalInfo?: string;
  };
}

export interface AppStoreSignedDataVerifier {
  verifyTransaction(jws: string): Promise<VerifiedTransaction>;
  verifyRenewalInfo(jws: string): Promise<VerifiedRenewalInfo>;
  verifyNotification(jws: string): Promise<VerifiedNotification>;
}

function decodeUntrustedEnvironment(jws: string): AppStoreEnvironment {
  const payloadSegment = jws.split(".")[1];
  if (!payloadSegment) throw new Error("Malformed App Store JWS.");
  const payload = JSON.parse(Buffer.from(payloadSegment, "base64url").toString("utf8")) as Record<
    string,
    unknown
  >;
  const data = typeof payload["data"] === "object" && payload["data"] !== null
    ? payload["data"] as Record<string, unknown>
    : undefined;
  const raw = payload["environment"] ?? data?.["environment"];
  if (raw === "Sandbox") return "sandbox";
  if (raw === "Production") return "production";
  throw new Error("Unsupported App Store environment.");
}

function readRootCertificates(): Buffer[] {
  const encoded = Deno.env.get("APP_STORE_ROOT_CA_CERTS_BASE64");
  if (!encoded) throw new AppStoreConfigurationError("Apple root certificates are not configured.");
  const certificates = encoded.split(",").map((value) => value.trim()).filter(Boolean);
  if (certificates.length === 0 || certificates.length > 8) {
    throw new AppStoreConfigurationError("Apple root certificate configuration is invalid.");
  }
  return certificates.map((value) => Buffer.from(value, "base64"));
}

function requiredAppAppleID(): number {
  const raw = Deno.env.get("APP_STORE_APPLE_ID");
  const value = raw ? Number(raw) : NaN;
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new AppStoreConfigurationError("Apple app ID configuration is invalid.");
  }
  return value;
}

function makeVerifier(environment: AppStoreEnvironment): SignedDataVerifier {
  const roots = readRootCertificates();
  const bundleId = Deno.env.get("APP_STORE_BUNDLE_ID") ?? "com.astrastyle.app";
  if (environment === "production") {
    return new EdgeAppStoreVerifier(
      roots,
      true,
      Environment.PRODUCTION,
      bundleId,
      requiredAppAppleID(),
    );
  }
  return new EdgeAppStoreVerifier(roots, true, Environment.SANDBOX, bundleId);
}

export const appStoreSignedDataVerifier: AppStoreSignedDataVerifier = {
  async verifyTransaction(jws) {
    const verifier = makeVerifier(decodeUntrustedEnvironment(jws));
    try {
      return await verifier.verifyAndDecodeTransaction(jws);
    } catch (error) {
      throw wrapVerificationError(error);
    }
  },
  async verifyRenewalInfo(jws) {
    const verifier = makeVerifier(decodeUntrustedEnvironment(jws));
    try {
      return await verifier.verifyAndDecodeRenewalInfo(jws);
    } catch (error) {
      throw wrapVerificationError(error);
    }
  },
  async verifyNotification(jws) {
    const verifier = makeVerifier(decodeUntrustedEnvironment(jws));
    try {
      return await verifier.verifyAndDecodeNotification(jws);
    } catch (error) {
      throw wrapVerificationError(error);
    }
  },
};

function wrapVerificationError(error: unknown): AppStoreVerificationError {
  // Static diagnostics only: never log JWS, transactions, certificate bytes or IDs.
  if (error instanceof VerificationException) {
    console.warn(JSON.stringify({
      event: "app_store_verification.failed",
      verification_status: error.status,
      cause_type: error.cause?.name ?? "none",
      reason: error.cause?.message.startsWith("edge_verifier:") ? error.cause.message : undefined,
      unsupported_api: error.cause?.message.startsWith("Not implemented:")
        ? error.cause.message.slice(0, 150)
        : undefined,
    }));
  }
  const retryable = error instanceof VerificationException &&
    error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE;
  return new AppStoreVerificationError(retryable, error);
}
