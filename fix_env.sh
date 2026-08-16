sed -i '\' /var/www/jyamiti-backend/.env

echo "RESEND_API_KEY=re_jAeGzaMo_7eWrSzE2dC9TTtp5d7ZYeT7y" >> /var/www/jyamiti-backend/.env

echo 'RESEND_FROM="Jyamiti Math Learning <noreply@jyamitimath.com>"' >> /var/www/jyamiti-backend/.env

pm2 restart jyamiti-backend --update-env
