import { StyleSheet } from 'react-native';

export function createRootLayoutStyles(backgroundColor: string) {
  return StyleSheet.create({
    safeArea: {
      flex: 1,
      backgroundColor,
    },
    content: {
      flex: 1,
    },
  });
}
