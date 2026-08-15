import { OAuth2Client } from 'google-auth-library';

export const getGoogleToken = async (req, res) => {
  try {
    const { scope } = req.query; // 'drive' or 'youtube'
    
    // Get credentials from environment variables
    const clientId = process.env.GOOGLE_CLIENT_ID;
    const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
    
    let refreshToken;
    if (scope === 'drive') {
      refreshToken = process.env.GOOGLE_DRIVE_REFRESH_TOKEN;
    } else if (scope === 'youtube') {
      refreshToken = process.env.GOOGLE_YOUTUBE_REFRESH_TOKEN;
    } else {
      return res.status(400).json({ error: 'Invalid or missing scope parameter (must be drive or youtube)' });
    }

    if (!clientId || !clientSecret || !refreshToken) {
      return res.status(500).json({ error: `Google OAuth credentials missing in backend for scope: ${scope}.` });
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
