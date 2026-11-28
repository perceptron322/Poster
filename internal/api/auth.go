package api

import (
	"context"
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"errors"
	"net/http"
	"net/mail"
	"strings"
)

type user struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
	Role  string `json:"role"`
}

const cookieName = "poster_session"
const sessionSeconds = 7 * 24 * 60 * 60

func passwordHash(password string, salt []byte) ([]byte, error) {
	return pbkdf2.Key(sha256.New, password, salt, 600000, 32)
}

func (s *server) cookie(r request, token string, age int) {
	http.SetCookie(r.writer, &http.Cookie{Name: cookieName, Value: token, Path: "/api/v1", HttpOnly: true,
		SameSite: http.SameSiteStrictMode, Secure: s.secureCookie || r.TLS != nil, MaxAge: age})
}

func sessionHash(r request) ([]byte, error) {
	c, err := r.Cookie(cookieName)
	if err != nil {
		return nil, unauthorized
	}
	b, err := hex.DecodeString(c.Value)
	if err != nil || len(b) != 32 {
		return nil, unauthorized
	}
	sum := sha256.Sum256(b)
	return sum[:], nil
}

func (s *server) currentUser(r request) (user, error) {
	var u user
	hash, err := sessionHash(r)
	if err != nil {
		return u, err
	}
	err = s.db.QueryRowContext(r.Context(), `
		SELECT u.user_id,u.name,u.email,u.role FROM user_sessions s JOIN users u USING(user_id)
		WHERE s.token_hash=$1 AND s.expires_at>now()`, hash).Scan(&u.ID, &u.Name, &u.Email, &u.Role)
	if errors.Is(err, sql.ErrNoRows) {
		return u, unauthorized
	}
	return u, err
}

func newSession(ctx context.Context, tx *sql.Tx, id int) (string, error) {
	token := make([]byte, 32)
	rand.Read(token)
	hash := sha256.Sum256(token)
	if _, err := tx.ExecContext(ctx, "DELETE FROM user_sessions WHERE expires_at <= now()"); err != nil {
		return "", err
	}
	_, err := tx.ExecContext(ctx, `INSERT INTO user_sessions(token_hash,user_id,expires_at)
		VALUES ($1,$2,now()+$3*interval '1 second')`, hash[:], id, sessionSeconds)
	return hex.EncodeToString(token), err
}

func (s *server) register(r request) (any, error) {
	var in struct {
		Name     string `json:"name"`
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	in.Name = strings.TrimSpace(in.Name)
	in.Email = strings.ToLower(strings.TrimSpace(in.Email))
	addr, err := mail.ParseAddress(in.Email)
	if err != nil || addr.Address != in.Email || !validText(in.Email, 255) || !validText(in.Name, 200) {
		return nil, invalid("Проверьте имя и email")
	}
	if len(in.Password) < 8 || len(in.Password) > 1024 {
		return nil, invalid("Длина пароля должна составлять от 8 до 1024 байт")
	}
	salt := make([]byte, 16)
	rand.Read(salt)
	hash, err := passwordHash(in.Password, salt)
	if err != nil {
		return nil, err
	}
	var token string
	u, err := transaction(r.Context(), s.db, func(tx *sql.Tx) (user, error) {
		u := user{Name: in.Name, Email: in.Email, Role: "customer"}
		err := tx.QueryRowContext(r.Context(), `INSERT INTO users(name,email,role)
			SELECT $1,$2::text,'customer' WHERE NOT EXISTS (SELECT FROM users WHERE lower(email)=$2)
			RETURNING user_id`, in.Name, in.Email).Scan(&u.ID)
		if errors.Is(err, sql.ErrNoRows) {
			return u, conflict("Email уже зарегистрирован")
		}
		if err != nil {
			return u, err
		}
		_, err = tx.ExecContext(r.Context(), "INSERT INTO user_credentials(user_id,password_salt,password_hash) VALUES ($1,$2,$3)", u.ID, salt, hash)
		if err != nil {
			return u, err
		}
		token, err = newSession(r.Context(), tx, u.ID)
		return u, err
	})
	if err == nil {
		s.cookie(r, token, sessionSeconds)
	}
	return u, err
}

func (s *server) login(r request) (any, error) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if in.Email == "" || in.Password == "" || len(in.Password) > 1024 {
		return nil, invalid("Укажите email и пароль допустимой длины")
	}
	var u user
	var salt, stored []byte
	err := s.db.QueryRowContext(r.Context(), `SELECT u.user_id,u.name,u.email,u.role,c.password_salt,c.password_hash
		FROM users u JOIN user_credentials c USING(user_id) WHERE u.email=$1`, strings.ToLower(strings.TrimSpace(in.Email))).Scan(&u.ID, &u.Name, &u.Email, &u.Role, &salt, &stored)
	if errors.Is(err, sql.ErrNoRows) {
		salt = make([]byte, 16)
	} else if err != nil {
		return nil, err
	}
	hash, err := passwordHash(in.Password, salt)
	if err != nil {
		return nil, err
	}
	if subtle.ConstantTimeCompare(hash, stored) != 1 {
		return nil, &problem{401, "invalid_credentials", "Неверный email или пароль"}
	}
	token, err := transaction(r.Context(), s.db, func(tx *sql.Tx) (string, error) { return newSession(r.Context(), tx, u.ID) })
	if err == nil {
		s.cookie(r, token, sessionSeconds)
	}
	return u, err
}

func (s *server) logout(r request) (any, error) {
	hash, err := sessionHash(r)
	if err != nil {
		return nil, err
	}
	_, err = s.db.ExecContext(r.Context(), "DELETE FROM user_sessions WHERE token_hash=$1", hash)
	if err == nil {
		s.cookie(r, "", -1)
	}
	return nil, err
}
