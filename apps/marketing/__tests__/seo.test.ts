import { describe, it, expect } from "vitest";
import { buildMetadata, organizationJsonLd, softwareAppJsonLd } from "@/lib/seo";
import { site } from "@/lib/site";

describe("seo", () => {
  it("buildMetadata sets canonical + OG", () => {
    const m = buildMetadata({ title: "Privacy", path: "/privacy" });
    expect(m.alternates?.canonical).toBe(`${site.url}/privacy`);
    expect(m.openGraph?.title).toBe("Privacy");
    expect(m.robots).toMatchObject({ index: true, follow: true });
  });
  it("Organization JSON-LD has the right type", () => {
    expect(organizationJsonLd()["@type"]).toBe("Organization");
    expect(softwareAppJsonLd()["@type"]).toBe("SoftwareApplication");
  });
});
