import { useRouter } from 'expo-router';
import { useEffect } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';

export default function NeoIdCallbackScreen() {
  const router = useRouter();
  const theme = useTheme();

  useEffect(() => {
    // Redirect to profile after a brief moment
    // The actual OAuth handling is done in the loginViaNeoId function
    const timer = setTimeout(() => {
      router.replace('/profile');
    }, 500);

    return () => clearTimeout(timer);
  }, [router]);

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <ActivityIndicator size="large" color={theme.accent} />
      <ThemedText style={styles.text}>Завершение авторизации...</ThemedText>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
  },
  text: {
    fontSize: 16,
  },
});
