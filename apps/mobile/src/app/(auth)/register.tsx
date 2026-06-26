import { useState } from "react";
import { Pressable } from "react-native";
import { useRouter } from "expo-router";
import { Screen } from "../../ui/Screen";
import { Text } from "../../ui/Text";
import { TextField } from "../../ui/TextField";
import { Button } from "../../ui/Button";
import { auth } from "../../api/auth";
import { useAuth } from "../../auth/store";

function isAdult(dob: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dob);
  if (!m) return false;
  const d = new Date(`${dob}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return false;
  const now = new Date();
  let age = now.getUTCFullYear() - d.getUTCFullYear();
  const md = now.getUTCMonth() - d.getUTCMonth() || now.getUTCDate() - d.getUTCDate();
  if (md < 0) age -= 1;
  return age >= 18;
}

export default function Register() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [dob, setDob] = useState("");
  const [accepted, setAccepted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const signIn = useAuth((s) => s.signIn);
  const router = useRouter();

  async function onSubmit() {
    setError(null);
    if (!isAdult(dob)) {
      setError("Debes ser mayor de 18 años.");
      return;
    }
    if (password.length < 8) {
      setError("La contraseña debe tener al menos 8 caracteres.");
      return;
    }
    if (!accepted) {
      setError("Debes aceptar los términos.");
      return;
    }
    setLoading(true);
    try {
      const pair = await auth.register({
        email,
        password,
        dob,
        consents: ["tos", "privacy", "age"],
      });
      await signIn(pair);
      router.replace("/(auth)/verify-email");
    } catch {
      setError("No se pudo crear la cuenta.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Screen>
      <Text style={{ fontSize: 28, fontWeight: "700" }}>Crear cuenta</Text>
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
      <TextField
        label="Fecha de nacimiento (YYYY-MM-DD)"
        autoCapitalize="none"
        value={dob}
        onChangeText={setDob}
      />
      <Pressable onPress={() => setAccepted((a) => !a)} testID="accept-terms">
        <Text style={{ color: "#9A9AA2" }}>
          {accepted ? "☑" : "☐"} Acepto términos y privacidad (18+)
        </Text>
      </Pressable>
      {error ? <Text style={{ color: "#E5484D" }}>{error}</Text> : null}
      <Button
        title="Crear cuenta"
        onPress={onSubmit}
        loading={loading}
        testID="register-submit"
      />
    </Screen>
  );
}
