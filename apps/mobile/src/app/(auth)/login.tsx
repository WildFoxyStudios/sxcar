import { useState } from "react";
import { Link, useRouter } from "expo-router";
import { Screen } from "../../ui/Screen";
import { Text } from "../../ui/Text";
import { TextField } from "../../ui/TextField";
import { Button } from "../../ui/Button";
import { auth } from "../../api/auth";
import { useAuth } from "../../auth/store";

export default function Login() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const signIn = useAuth((s) => s.signIn);
  const router = useRouter();

  async function onSubmit() {
    setLoading(true);
    setError(null);
    try {
      const pair = await auth.login({ email, password });
      await signIn(pair);
      router.replace("/(app)");
    } catch {
      setError("Email o contraseña incorrectos.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Screen>
      <Text style={{ fontSize: 28, fontWeight: "700" }}>Entrar</Text>
      <TextField
        label="Email"
        autoCapitalize="none"
        keyboardType="email-address"
        value={email}
        onChangeText={setEmail}
      />
      <TextField
        label="Contraseña"
        secureTextEntry
        value={password}
        onChangeText={setPassword}
      />
      {error ? <Text style={{ color: "#E5484D" }}>{error}</Text> : null}
      <Button title="Entrar" onPress={onSubmit} loading={loading} testID="login-submit" />
      <Link href="/(auth)/register">
        <Text style={{ color: "#9A9AA2" }}>Crear cuenta</Text>
      </Link>
    </Screen>
  );
}
