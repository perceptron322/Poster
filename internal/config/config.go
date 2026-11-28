package config

import (
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
)

type Config struct {
	ServerPort   string
	DatabaseURL  string
	MongoURI     string
	MongoDB      string
	CookieSecure bool
}

func Load() (*Config, error) {
	dbURL, err := databaseURL()
	if err != nil {
		return nil, err
	}
	secure, err := strconv.ParseBool(envOr("COOKIE_SECURE", "false"))
	if err != nil {
		return nil, fmt.Errorf("COOKIE_SECURE: %w", err)
	}
	return &Config{
		CookieSecure: secure,
		ServerPort:   envOr("SERVER_PORT", "8081"),
		DatabaseURL:  dbURL,
		MongoURI:     mongoURI(),
		MongoDB:      envOr("MONGO_DB", "poster_content"),
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
		RawQuery: "sslmode=" + envOr("POSTGRES_SSLMODE", "require"),
	}
	return u.String(), nil
}

func mongoURI() string {
	if uri := os.Getenv("MONGO_URI"); uri != "" {
		return uri
	}
	u := url.URL{Scheme: "mongodb", Host: net.JoinHostPort(envOr("MONGO_HOST", "localhost"), envOr("MONGO_PORT", "27018"))}
	if password := os.Getenv("MONGO_PASSWORD"); password != "" {
		u.User = url.UserPassword(envOr("MONGO_USER", "poster"), password)
		u.Path = "/"
		u.RawQuery = "authSource=admin"
	}
	return u.String()
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
