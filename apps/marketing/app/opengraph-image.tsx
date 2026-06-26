import { ImageResponse } from "next/og";
import { site } from "@/lib/site";

export const alt = site.tagline;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          background: "#0a0a0a",
          color: "#ffffff",
        }}
      >
        <div style={{ fontSize: 72, fontWeight: 800 }}>{site.name}</div>
        <div style={{ fontSize: 32, color: "#d4d4d4", marginTop: 16 }}>
          {site.tagline}
        </div>
      </div>
    ),
    { ...size }
  );
}
