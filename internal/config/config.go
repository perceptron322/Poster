package config

import (
	"fmt"
	"net/url"
	"os"
)

type Config struct {
	ServerPort  string
	DatabaseURL string
}

func Load() (*Config, error) {
	dbURL, err := databaseURL()
	if err != nil {
		return nil, err
	}
	return &Config{
		ServerPort:  envOr("SERVER_PORT", "8081"),
		DatabaseURL: dbURL,
	}, nil
}

func (c *Config) String() string {
	return fmt.Sprintf("Config{ServerPort:%s DatabaseURL:%s}", c.ServerPort, redact(c.DatabaseURL))
}

func databaseURL() (string, error) {
	if v := os.Getenv("DATABASE_URL"); v != "" {
		return v, nil
	}
	password, err := required("POSTGRES_PASSWORD")
	if err != nil {
		return "", err
	}
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(envOr("POSTGRES_USER", "poster"), password),
		Host:     envOr("POSTGRES_HOST", "localhost") + ":" + envOr("POSTGRES_PORT", "5433"),
		Path:     "/" + envOr("POSTGRES_DB", "poster"),
		RawQuery: "sslmode=" + envOr("POSTGRES_SSLMODE", "disable"),
	}
	return u.String(), nil
}

func required(key string) (string, error) {
	v := os.Getenv(key)
	if v == "" {
		return "", fmt.Errorf("переменная окружения %s не задана", key)
	}
	return v, nil
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func redact(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return "<invalid url>"
	}
	return u.Redacted()
}
