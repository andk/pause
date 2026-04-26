CREATE TABLE auth_tokens (
  id INTEGER AUTO_INCREMENT PRIMARY KEY,
  user VARCHAR(9) NOT NULL,
  token_id VARCHAR(32) NOT NULL,
  token_hash VARCHAR(64) NOT NULL,
  description VARCHAR(255),
  expires_at DATETIME NOT NULL,
  ip_ranges TEXT,
  scope TEXT,
  revoked TINYINT DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user, token_id),
  INDEX(user, token_id, token_hash),
  INDEX(user, revoked)
);

CREATE TABLE auth_log (
  id INTEGER AUTO_INCREMENT PRIMARY KEY,
  user VARCHAR(9) NOT NULL,
  token_id VARCHAR(32) DEFAULT '',
  ip VARCHAR(16) NOT NULL,
  error TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX(user, token_id),
  INDEX(user, ip)
);
