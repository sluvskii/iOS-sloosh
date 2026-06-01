import { StyleSheet } from 'react-native';
import { Spacing } from '@/constants/theme';

type ThemePalette = {
  border: string;
  backgroundElement: string;
  chrome: string;
};

export const navBarStyles = StyleSheet.create({
  container: {
    width: '100%',
    paddingHorizontal: 0,
    paddingTop: 10,
    paddingBottom: 10,
    borderTopWidth: 0,
  },
  transparentBackground: {
    backgroundColor: 'transparent',
  },
  tabBar: {
    flexDirection: 'row',
    paddingVertical: 0,
    paddingHorizontal: Spacing.six,
    justifyContent: 'space-between',
    alignItems: 'center',
    alignSelf: 'stretch',
  },
  tabItem: {
    flex: 1,
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  tabItemActive: {
    backgroundColor: 'transparent',
  },
  tabItemPressed: {
    opacity: 0.6,
  },
  iconWrapper: {
    width: 28,
    height: 28,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatar: {
    width: 28,
    height: 28,
    borderRadius: 14,
  },
});

export function createNavBarThemeStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: {
      borderTopColor: 'transparent',
      backgroundColor: theme.chrome,
    },
    tabBar: {
      backgroundColor: 'transparent',
      borderColor: 'transparent',
    },
  });
}
