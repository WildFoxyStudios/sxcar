import { useEffect } from "react";
import { Slot, useRouter, useSegments } from "expo-router";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { useAuth } from "../auth/store";

const qc = new QueryClient();

function Gate() {
  const status = useAuth((s) => s.status);
  const hydrate = useAuth((s) => s.hydrate);
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => { hydrate(); }, [hydrate]);

  useEffect(() => {
    if (status === "loading") return;
    const inAuth = segments[0] === "(auth)";
    const inApp = segments[0] === "(app)";
    if (status === "signedOut" && !inAuth) router.replace("/(auth)/login");
    else if (status === "signedIn" && !inApp) router.replace("/(app)");
  }, [status, segments, router]);

  return <Slot />;
}

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <QueryClientProvider client={qc}>
        <Gate />
      </QueryClientProvider>
    </SafeAreaProvider>
  );
}
