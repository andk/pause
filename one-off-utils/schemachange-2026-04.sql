CREATE TABLE auth_tokens (
  id INTEGER AUTO_INCREMENT PRIMARY KEY,
  user VARCHAR(9),
  token_id VARCHAR(8),
  token_hash VARCHAR(64),
  description VARCHAR(255),
  expires_at DATETIME NOT NULL,
  ip_ranges TEXT,
  scope TEXT,
  revoked TINYINT DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX(user, token_id, token_hash),
  INDEX(user, revoked)
);
