source ./scripts/shared/load.sh

echo
echo "docker ps -a"
docker ps -a
echo
echo "Copy-paste ready command:"
echo
echo "mariadb -h localhost -P ${MARIADB_PORT} -u ${MARIADB_USER} -p${MARIADB_PASSWORD} ${MARIADB_DATABASE}"
echo
echo "Then run the following SQL commands to set up the database and user:"
echo
