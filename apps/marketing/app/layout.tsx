import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "proyecto-X",
  description: "Marketing site",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
