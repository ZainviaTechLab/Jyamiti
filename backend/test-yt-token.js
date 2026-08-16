import { OAuth2Client } from 'google-auth-library';
import dotenv from 'dotenv';
dotenv.config();

const clientId = process.env.GOOGLE_CLIENT_ID;
const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
const refreshToken = process.env.GOOGLE_YOUTUBE_REFRESH_TOKEN;

const oAuth2Client = new OAuth2Client(clientId, clientSecret);
oAuth2Client.setCredentials({ refresh_token: refreshToken });

async function testToken() {
  try {
    const { token } = await oAuth2Client.getAccessToken();
    console.log("Success! Token:", token.substring(0, 10) + "...");
  } catch (error) {
    console.error("Error generating token:", error.response?.data || error.message);
  }
}

testToken();
