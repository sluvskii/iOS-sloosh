import { StyleSheet } from 'react-native';

import { Radius, Spacing } from '@/constants/theme';

type ThemePalette = {
  backgroundElement: string;
  border: string;
  text: string;
  textSecondary: string;
  accent: string;
  backgroundSelected: string;
  danger: string;
};

export function createProfileScreenStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: { flex: 1 },
    content: {
      paddingHorizontal: Spacing.four,
      paddingTop: Spacing.four,
      paddingBottom: 120,
      gap: Spacing.four,
    },
    profileCard: {
      borderWidth: 0,
      borderColor: 'transparent',
      borderRadius: Radius.xl,
      backgroundColor: theme.backgroundElement,
      padding: Spacing.five,
      gap: Spacing.three,
      alignItems: 'center',
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.06,
      shadowRadius: 12,
      elevation: 3,
    },
    profileTitle: {
      fontSize: 24,
      lineHeight: 30,
      fontWeight: '700',
      textAlign: 'center',
      letterSpacing: -0.5,
    },
    profileEmail: {
      fontSize: 15,
      lineHeight: 22,
      color: theme.textSecondary,
      textAlign: 'center',
    },
    loginButton: {
      minHeight: 52,
      borderRadius: Radius.lg,
      borderWidth: 0,
      borderColor: 'transparent',
      backgroundColor: theme.accent,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: Spacing.four,
      marginTop: Spacing.two,
      shadowColor: theme.accent,
      shadowOffset: { width: 0, height: 4 },
      shadowOpacity: 0.2,
      shadowRadius: 8,
      elevation: 4,
      alignSelf: 'stretch',
    },
    loginButtonContent: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: Spacing.three,
    },
    loginButtonText: {
      color: '#FFFFFF',
      fontSize: 16,
      lineHeight: 22,
      fontWeight: '700',
    },
    avatar: {
      width: 96,
      height: 96,
      borderRadius: 48,
      borderWidth: 0,
      borderColor: 'transparent',
    },
    menu: {
      borderWidth: 0,
      borderColor: 'transparent',
      borderRadius: Radius.xl,
      backgroundColor: theme.backgroundElement,
      overflow: 'hidden',
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.06,
      shadowRadius: 12,
      elevation: 3,
    },
    menuItem: {
      minHeight: 64,
      paddingHorizontal: Spacing.four,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      borderBottomWidth: 1,
      borderBottomColor: theme.border,
    },
    menuItemLast: {
      borderBottomWidth: 0,
    },
    menuItemLeft: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.three,
    },
    menuItemLabel: {
      fontSize: 16,
      lineHeight: 22,
      fontWeight: '600',
      color: theme.text,
    },
    logoutButton: {
      minHeight: 56,
      borderRadius: Radius.lg,
      borderWidth: 0,
      borderColor: 'transparent',
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: theme.accent,
      shadowColor: theme.accent,
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.2,
      shadowRadius: 8,
      elevation: 4,
    },
    logoutText: {
      fontSize: 16,
      lineHeight: 22,
      fontWeight: '600',
      color: '#FFFFFF',
    },
    errorText: {
      fontSize: 14,
      lineHeight: 20,
      color: theme.danger,
      textAlign: 'center',
    },
  });
}
