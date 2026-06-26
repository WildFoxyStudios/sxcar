import { useState } from "react";
import { useRouter } from "expo-router";
import { Screen } from "../../ui/Screen";
import { Text } from "../../ui/Text";
import { TextField } from "../../ui/TextField";
import { Button } from "../../ui/Button";
import { auth } from "../../api/auth";

export default function VerifyEmail() {
  const [code, setCode] = useState("");
  const [msg, setMsg] = useState<string | null>(null);
  const router = useRouter();

  async function verify() {
    const res = await auth.verifyEmail(code);
    setMsg(res.ok ? "Email verificado." : "Código inválido.");
    if (res.ok) router.replace("/(app)");
  }

  return (
    <Screen>
      <Text style={{ fontSize: 28, fontWeight: "700" }}>Verifica tu email</Text>
      <Text style={{ color: "#9A9AA2" }}>Introduce el código que te enviamos.</Text>
      <TextField
        label="Código"
        keyboardType="number-pad"
        value={code}
        onChangeText={setCode}
      />
      {msg ? <Text>{msg}</Text> : null}
      <Button title="Verificar" onPress={verify} testID="verify-submit" />
      <Button title="Reenviar" onPress={() => auth.resendEmail()} />
    </Screen>
  );
}
