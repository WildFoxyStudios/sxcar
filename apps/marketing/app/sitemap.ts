import type { MetadataRoute } from "next";
import { site } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  const routes = ["", "/privacy", "/terms", "/support", "/blog"];
  return routes.map((r) => ({
    url: `${site.url}${r}`,
    lastModified: new Date("2026-06-26"),
    changeFrequency: "weekly" as const,
    priority: r === "" ? 1 : 0.7,
  }));
}
