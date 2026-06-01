export type NeoIdTokens = {
  accessToken: string;
  refreshToken?: string;
};

export type NeoIdUserProfile = {
  unified_id?: string;
  neo_id?: string;
  id?: string;
  email?: string;
  name?: string;
  display_name?: string;
  first_name?: string;
  last_name?: string;
  avatar?: string;
  role?: string;
  is_admin?: boolean;
  age_confirmed_16_plus?: boolean;
};

export type NeoIdPasswordLoginResponse = {
  access_token?: string;
  refresh_token?: string;
  verify_type?: string;
  message?: string;
};
