import { View, ActivityIndicator } from "react-native";

export default function Index() {
  return (
    <View
      style={{
        flex: 1,
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: "#0E0E10",
      }}
    >
      <ActivityIndicator color="#F5C518" />
    </View>
  );
}
