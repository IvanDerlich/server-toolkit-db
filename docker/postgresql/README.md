# Check it's listening to all addresses

```sh
sudo docker exec -it vaultwarden sh -lc 'cat /var/lib/postgresql/data/postgresql.conf | grep -E "^[[:space:]]*listen_addresses"'
```

# Connect

psql "postgresql://USER:PASSWORD@IP:PORT/DATABASE"
