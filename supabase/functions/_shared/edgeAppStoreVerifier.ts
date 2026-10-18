/*
OCSP verification adapted from apple/app-store-server-library-node 3.1.0.
Copyright 2023 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
/// <reference types="npm:@types/jsrsasign@10.5.15" />

import { Buffer } from "node:buffer";
import { createHash, type KeyObject, verify, X509Certificate } from "node:crypto";
import {
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "npm:@apple/app-store-server-library@3.1.0";
import type { Validator } from "npm:@apple/app-store-server-library@3.1.0/dist/models/Validator.js";
import { ASN1HEX, KJUR, X509 } from "npm:jsrsasign@11.1.5";

/**
 * Deno 2.1 (the hosted Edge runtime) lacks X509Certificate.raw, toString,
 * verify and infoAccess. Adapt only certificate representation/operations;
 * Apple's pinned verifier still enforces its complete chain, OIDs, dates
 * and app/environment checks. This adapter retains OCSP and verifies ES256
 * directly because Deno 2.1's EC curve alias also breaks jsonwebtoken. See ADR 0047.
 * Each instance is request-scoped and verifies one JWS at a time.
 */
export class EdgeAppStoreVerifier extends SignedDataVerifier {
  private certificateDER: Buffer[] = [];

  protected override async verifyJWT<T>(
    jwt: string,
    validator: Validator<T>,
    signedDateExtractor: (payload: T) => Date,
  ): Promise<T> {
    try {
      const parts = jwt.split(".");
      const [headerPart, payloadPart, signaturePart] = parts;
      if (parts.length !== 3 || !headerPart || !payloadPart || !signaturePart) {
        throw new VerificationException(VerificationStatus.FAILURE);
      }
      const header = JSON.parse(Buffer.from(headerPart, "base64url").toString());
      const payload: unknown = JSON.parse(Buffer.from(payloadPart, "base64url").toString());
      if (!validator.validate(payload) || header.alg !== "ES256") {
        throw new VerificationException(VerificationStatus.FAILURE);
      }
      if (
        !Array.isArray(header.x5c) || header.x5c.length !== 3 ||
        !header.x5c.every((value: unknown) => typeof value === "string")
      ) {
        throw new VerificationException(VerificationStatus.INVALID_CHAIN_LENGTH);
      }
      this.certificateDER = header.x5c.map((value: string) => Buffer.from(value, "base64"));
      const leafDER = this.certificateDER[0];
      const intermediateDER = this.certificateDER[1];
      if (!leafDER || !intermediateDER) {
        throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE);
      }
      const key = await this.verifyCertificateChain(
        this.rootCertificates,
        new X509Certificate(leafDER),
        new X509Certificate(intermediateDER),
        this.enableOnlineChecks ? new Date() : signedDateExtractor(payload),
      );
      const signature = Buffer.from(signaturePart, "base64url");
      if (key.asymmetricKeyType !== "ec" || signature.length !== 64) {
        throw new VerificationException(
          VerificationStatus.VERIFICATION_FAILURE,
          new Error("edge_verifier:key_type"),
        );
      }
      // Import enforces P-256. WebCrypto consumes JWS's raw R||S signature;
      // Deno 2.1's node:crypto also mishandles the ieee-p1363 option.
      const signingKey = await crypto.subtle.importKey(
        "spki",
        new Uint8Array(key.export({ type: "spki", format: "der" })),
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["verify"],
      );
      if (
        !await crypto.subtle.verify(
          { name: "ECDSA", hash: "SHA-256" },
          signingKey,
          new Uint8Array(signature),
          new TextEncoder().encode(`${headerPart}.${payloadPart}`),
        )
      ) {
        throw new VerificationException(
          VerificationStatus.VERIFICATION_FAILURE,
          new Error("edge_verifier:jws_signature"),
        );
      }
      const claims = payload as Record<string, unknown>;
      const now = Math.floor(Date.now() / 1000);
      if (
        (claims.exp !== undefined &&
          (typeof claims.exp !== "number" || now >= claims.exp)) ||
        (claims.nbf !== undefined &&
          (typeof claims.nbf !== "number" || now < claims.nbf))
      ) {
        throw new VerificationException(VerificationStatus.FAILURE);
      }
      return payload;
    } catch (error) {
      if (error instanceof VerificationException) throw error;
      throw new VerificationException(
        VerificationStatus.VERIFICATION_FAILURE,
        error instanceof Error ? error : undefined,
      );
    }
  }

  protected override async verifyCertificateChain(
    roots: X509Certificate[],
    leaf: X509Certificate,
    intermediate: X509Certificate,
    date: Date,
  ): Promise<KeyObject> {
    const leafDER = this.certificateDER[0];
    const intermediateDER = this.certificateDER[1];
    if (!leafDER || !intermediateDER) throw new Error("Missing Apple certificate chain.");
    adaptCertificate(leaf, leafDER);
    adaptCertificate(intermediate, intermediateDER);
    try {
      return await super.verifyCertificateChain(roots, leaf, intermediate, date);
    } catch (error) {
      if (error instanceof VerificationException && !error.cause) {
        throw new VerificationException(error.status, new Error("edge_verifier:certificate_chain"));
      }
      throw error;
    }
  }

  constructor(...args: ConstructorParameters<typeof SignedDataVerifier>) {
    super(...args);
    this.rootCertificates.forEach((certificate, index) => {
      const der = args[0][index];
      if (!der) throw new Error("Missing Apple trust root.");
      adaptCertificate(certificate, der);
    });
  }

  // Apple's OCSP routine also constructs responder certificates internally.
  // Preserve its checks while adapting those certificates and using native fetch.
  protected override async checkOCSPStatus(
    certificate: X509Certificate,
    issuer: X509Certificate,
  ): Promise<void> {
    const url = /^OCSP - URI:(.*)$/m.exec(certificate.infoAccess ?? "")?.[1];
    if (!url) throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE);
    const request = new KJUR.asn1.ocsp.OCSPRequest({
      reqList: [{
        issuerCert: issuer.toString(),
        subjectCert: certificate.toString(),
        alg: "sha256",
      }],
    });
    let bytes: Buffer;
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/ocsp-request" },
        body: new Uint8Array(Buffer.from(request.getEncodedHex(), "hex")),
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) throw new Error("OCSP responder unavailable.");
      bytes = Buffer.from(await response.arrayBuffer());
      if (bytes.length > 1_000_000) throw new Error("OCSP response too large.");
    } catch (error) {
      throw new VerificationException(
        VerificationStatus.RETRYABLE_VERIFICATION_FAILURE,
        error instanceof Error ? error : undefined,
      );
    }
    // jsrsasign's OCSPParser is shipped and used by Apple, but absent from its @types.
    const parserAPI = KJUR.asn1.ocsp as unknown as {
      OCSPParser: new () => { getOCSPResponse(hex: string): OCSPResponse };
    };
    const response = new parserAPI.OCSPParser().getOCSPResponse(bytes.toString("hex"));
    const issuerParsed = new X509();
    issuerParsed.readCertHex(issuer.raw.toString("hex"));
    const candidates = [
      issuerParsed,
      ...(response.certs ?? []).map((hex) => {
        const parsed = new X509();
        parsed.readCertHex(hex);
        return parsed;
      }),
    ];
    const signer = candidates.find((candidate) =>
      response.respid.key
        ? createHash("sha1").update(Buffer.from(candidate.getSPKIValue(), "hex")).digest("hex") ===
          response.respid.key
        : candidate.getSubject().str === response.respid.name?.str
    );
    if (!signer) {
      throw new VerificationException(
        VerificationStatus.FAILURE,
        new Error("edge_verifier:ocsp_signer_missing"),
      );
    }
    const signerDER = Buffer.from(signer.hex, "hex");
    const signingCertificate = new X509Certificate(signerDER);
    adaptCertificate(signingCertificate, signerDER);
    if (signer.hex !== issuerParsed.hex) {
      if (
        !signingCertificate.verify(issuer.publicKey) ||
        !signer.getExtExtKeyUsage()?.array.includes("ocspSigning")
      ) {
        throw new VerificationException(
          VerificationStatus.INVALID_CERTIFICATE,
          new Error("edge_verifier:ocsp_signer_invalid"),
        );
      }
      const now = Date.now();
      if (
        new Date(signingCertificate.validFrom).getTime() > now + 60_000 ||
        new Date(signingCertificate.validTo).getTime() < now - 60_000
      ) {
        throw new VerificationException(
          VerificationStatus.INVALID_CERTIFICATE,
          new Error("edge_verifier:ocsp_signer_dates"),
        );
      }
    }
    const algorithm = response.alg.substring(0, 6).toUpperCase();
    const responseData = ASN1HEX.getTLVbyList(bytes.toString("hex"), 0, [1, 0, 1, 0, 0]);
    if (
      !responseData || !["SHA256", "SHA384", "SHA512"].includes(algorithm) ||
      !verify(
        algorithm,
        Buffer.from(responseData, "hex"),
        signingCertificate.publicKey,
        Buffer.from(response.sighex, "hex"),
      )
    ) {
      throw new VerificationException(
        VerificationStatus.FAILURE,
        new Error("edge_verifier:ocsp_response_signature"),
      );
    }
    const builder = new KJUR.asn1.ocsp.CertID() as unknown as {
      getParamByCerts(issuer: string, subject: string, alg: string): Record<string, string>;
    };
    const expected = builder.getParamByCerts(
      issuer.toString(),
      certificate.toString(),
      "sha256",
    );
    const entry = response.array.find((item) =>
      ["alg", "issname", "isskey", "sbjsn"].every((key) => expected[key] === item.certid[key])
    );
    if (
      !entry || entry.status.status !== "good" ||
      !validOCSPDates(entry.thisupdate, entry.nextupdate)
    ) {
      throw new VerificationException(
        VerificationStatus.FAILURE,
        new Error("edge_verifier:ocsp_status"),
      );
    }
  }
}

interface OCSPResponse {
  certs?: string[];
  respid: { key?: string; name?: { str: string } };
  alg: string;
  sighex: string;
  array: {
    certid: Record<string, string>;
    status: { status: string };
    thisupdate: string;
    nextupdate: string;
  }[];
}

function validOCSPDates(issued: string, next: string): boolean {
  const parse = (value: string) =>
    new Date(
      value.replace(/^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)Z?$/, "$1-$2-$3T$4:$5:$6Z"),
    ).getTime();
  const now = Date.now();
  return parse(issued) <= now + 60_000 && parse(next) >= now - 60_000;
}

function adaptCertificate(certificate: X509Certificate, der: Buffer): void {
  const parsed = new X509();
  parsed.readCertHex(der.toString("hex"));
  const pem = `-----BEGIN CERTIFICATE-----\n${
    der.toString("base64").match(/.{1,64}/g)?.join("\n") ?? ""
  }\n-----END CERTIFICATE-----`;
  const access = parsed.getExtAIAInfo();
  Object.defineProperties(certificate, {
    raw: { value: der, configurable: true },
    toString: { value: () => pem, configurable: true },
    infoAccess: {
      value: access?.ocsp?.map((uri) => `OCSP - URI:${uri}`).join("\n"),
      configurable: true,
    },
    verify: {
      value: (key: KeyObject) => {
        const algorithm = /^(SHA256|SHA384|SHA512)with(?:ECDSA|RSA)$/
          .exec(parsed.getSignatureAlgorithmField())?.[1];
        const tbs = ASN1HEX.getTLVbyList(parsed.hex, 0, [0], "30");
        if (!algorithm || !tbs) return false;
        try {
          return verify(
            algorithm.toLowerCase(),
            Buffer.from(tbs, "hex"),
            key,
            Buffer.from(parsed.getSignatureValueHex(), "hex"),
          );
        } catch {
          return false;
        }
      },
      configurable: true,
    },
  });
}
