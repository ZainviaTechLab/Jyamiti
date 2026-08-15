import { OAuth2Client } from 'google-auth-library';

export const getGoogleToken = async (req, res) => {
  try {
    // Get credentials from environment variables
    const clientId = process.env.GOOGLE_CLIENT_ID;
    const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
    const refreshToken = process.env.GOOGLE_REFRESH_TOKEN;

    if (!clientId || !clientSecret || !refreshToken) {
      return res.status(500).json({ error: 'Google OAuth credentials missing in backend.' });
    }

    const oAuth2Client = new OAuth2Client(clientId, clientSecret);
    oAuth2Client.setCredentials({ refresh_token: refreshToken });

    // This gets a fresh access token using the refresh token
    const { token } = await oAuth2Client.getAccessToken();

    res.status(200).json({ access_token: token });
  } catch (error) {
    console.error('Error generating Google token:', error);
    res.status(500).json({ error: 'Failed to generate token' });
  }
};
