import { Screen } from "../../ui/Screen";
import { Text } from "../../ui/Text";
import { Button } from "../../ui/Button";
import { useAuth } from "../../auth/store";
import { auth } from "../../api/auth";

export default function Home() {
  const { refreshToken, signOut } = useAuth();

  async function onLogout() {
    if (refreshToken) await auth.logout(refreshToken);
    await signOut();
  }

  return (
    <Screen>
      <Text style={{ fontSize: 28, fontWeight: "700" }}>proyecto-X</Text>
      <Text style={{ color: "#9A9AA2" }}>Aquí irá el grid de cercanos.</Text>
      <Button title="Cerrar sesión" onPress={onLogout} testID="logout" />
    </Screen>
  );
}
