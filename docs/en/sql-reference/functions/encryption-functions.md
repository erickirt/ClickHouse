---
description: 'Documentation for Encryption Functions'
sidebar_label: 'Encryption'
slug: /sql-reference/functions/encryption-functions
title: 'Encryption Functions'
---

# Encryption functions

These functions  implement encryption and decryption of data with AES (Advanced Encryption Standard) algorithm.

Key length depends on encryption mode. It is 16, 24, and 32 bytes long for `-128-`, `-196-`, and `-256-` modes respectively.

Initialization vector length is always 16 bytes (bytes in excess of 16 are ignored).

Note that these functions work slowly until ClickHouse 21.1.

## encrypt {#encrypt}

This function encrypts data using these modes:

- aes-128-ecb, aes-192-ecb, aes-256-ecb
- aes-128-cbc, aes-192-cbc, aes-256-cbc
- aes-128-ofb, aes-192-ofb, aes-256-ofb
- aes-128-gcm, aes-192-gcm, aes-256-gcm
- aes-128-ctr, aes-192-ctr, aes-256-ctr
- aes-128-cfb, aes-128-cfb1, aes-128-cfb8

**Syntax**

```sql
encrypt('mode', 'plaintext', 'key' [, iv, aad])
```

**Arguments**

- `mode` — Encryption mode. [String](/sql-reference/data-types/string).
- `plaintext` — Text that need to be encrypted. [String](/sql-reference/data-types/string).
- `key` — Encryption key. [String](/sql-reference/data-types/string).
- `iv` — Initialization vector. Required for `-gcm` modes, optional for others. [String](/sql-reference/data-types/string).
- `aad` — Additional authenticated data. It isn't encrypted, but it affects decryption. Works only in `-gcm` modes, for others would throw an exception. [String](/sql-reference/data-types/string).

**Returned value**

- Ciphertext binary string. [String](/sql-reference/data-types/string).

**Examples**

Create this table:

Query:

```sql
CREATE TABLE encryption_test
(
    `comment` String,
    `secret` String
)
ENGINE = Memory;
```

Insert some data (please avoid storing the keys/ivs in the database as this undermines the whole concept of encryption), also storing 'hints' is unsafe too and used only for illustrative purposes:

Query:

```sql
INSERT INTO encryption_test VALUES('aes-256-ofb no IV', encrypt('aes-256-ofb', 'Secret', '12345678910121314151617181920212')),\
('aes-256-ofb no IV, different key', encrypt('aes-256-ofb', 'Secret', 'keykeykeykeykeykeykeykeykeykeyke')),\
('aes-256-ofb with IV', encrypt('aes-256-ofb', 'Secret', '12345678910121314151617181920212', 'iviviviviviviviv')),\
('aes-256-cbc no IV', encrypt('aes-256-cbc', 'Secret', '12345678910121314151617181920212'));
```

Query:

```sql
SELECT comment, hex(secret) FROM encryption_test;
```

Result:

```text
┌─comment──────────────────────────┬─hex(secret)──────────────────────┐
│ aes-256-ofb no IV                │ B4972BDC4459                     │
│ aes-256-ofb no IV, different key │ 2FF57C092DC9                     │
│ aes-256-ofb with IV              │ 5E6CB398F653                     │
│ aes-256-cbc no IV                │ 1BC0629A92450D9E73A00E7D02CF4142 │
└──────────────────────────────────┴──────────────────────────────────┘
```

Example with `-gcm`:

Query:

```sql
INSERT INTO encryption_test VALUES('aes-256-gcm', encrypt('aes-256-gcm', 'Secret', '12345678910121314151617181920212', 'iviviviviviviviv')), \
('aes-256-gcm with AAD', encrypt('aes-256-gcm', 'Secret', '12345678910121314151617181920212', 'iviviviviviviviv', 'aad'));

SELECT comment, hex(secret) FROM encryption_test WHERE comment LIKE '%gcm%';
```

Result:

```text
┌─comment──────────────┬─hex(secret)──────────────────────────────────┐
│ aes-256-gcm          │ A8A3CCBC6426CFEEB60E4EAE03D3E94204C1B09E0254 │
│ aes-256-gcm with AAD │ A8A3CCBC6426D9A1017A0A932322F1852260A4AD6837 │
└──────────────────────┴──────────────────────────────────────────────┘
```

## aes_encrypt_mysql {#aes_encrypt_mysql}

Compatible with mysql encryption and resulting ciphertext can be decrypted with [AES_DECRYPT](https://dev.mysql.com/doc/refman/8.0/en/encryption-functions.html#function_aes-decrypt) function.

Will produce the same ciphertext as `encrypt` on equal inputs. But when `key` or `iv` are longer than they should normally be, `aes_encrypt_mysql` will stick to what MySQL's `aes_encrypt` does: 'fold' `key` and ignore excess bits of `iv`.

Supported encryption modes:

- aes-128-ecb, aes-192-ecb, aes-256-ecb
- aes-128-cbc, aes-192-cbc, aes-256-cbc
- aes-128-ofb, aes-192-ofb, aes-256-ofb

**Syntax**

```sql
aes_encrypt_mysql('mode', 'plaintext', 'key' [, iv])
```

**Arguments**

- `mode` — Encryption mode. [String](/sql-reference/data-types/string).
- `plaintext` — Text that needs to be encrypted. [String](/sql-reference/data-types/string).
- `key` — Encryption key. If key is longer than required by mode, MySQL-specific key folding is performed. [String](/sql-reference/data-types/string).
- `iv` — Initialization vector. Optional, only first 16 bytes are taken into account [String](/sql-reference/data-types/string).

**Returned value**

- Ciphertext binary string. [String](/sql-reference/data-types/string).

**Examples**

Given equal input `encrypt` and `aes_encrypt_mysql` produce the same ciphertext:

Query:

```sql
SELECT encrypt('aes-256-ofb', 'Secret', '12345678910121314151617181920212', 'iviviviviviviviv') = aes_encrypt_mysql('aes-256-ofb', 'Secret', '12345678910121314151617181920212', 'iviviviviviviviv') AS ciphertexts_equal;
```

Result:

```response
┌─ciphertexts_equal─┐
│                 1 │
└───────────────────┘
```

But `encrypt` fails when `key` or `iv` is longer than expected:

Query:

```sql
SELECT encrypt('aes-256-ofb', 'Secret', '123456789101213141516171819202122', 'iviviviviviviviv123');
```

Result:

```text
Received exception from server (version 22.6.1):
Code: 36. DB::Exception: Received from localhost:9000. DB::Exception: Invalid key size: 33 expected 32: While processing encrypt('aes-256-ofb', 'Secret', '123456789101213141516171819202122', 'iviviviviviviviv123').
```

While `aes_encrypt_mysql` produces MySQL-compatible output:

Query:

```sql
SELECT hex(aes_encrypt_mysql('aes-256-ofb', 'Secret', '123456789101213141516171819202122', 'iviviviviviviviv123')) AS ciphertext;
```

Result:

```response
┌─ciphertext───┐
│ 24E9E4966469 │
└──────────────┘
```

Notice how supplying even longer `IV` produces the same result

Query:

```sql
SELECT hex(aes_encrypt_mysql('aes-256-ofb', 'Secret', '123456789101213141516171819202122', 'iviviviviviviviv123456')) AS ciphertext
```

Result:

```text
┌─ciphertext───┐
│ 24E9E4966469 │
└──────────────┘
```

Which is binary equal to what MySQL produces on same inputs:

```sql
mysql> SET  block_encryption_mode='aes-256-ofb';
Query OK, 0 rows affected (0.00 sec)

mysql> SELECT aes_encrypt('Secret', '123456789101213141516171819202122', 'iviviviviviviviv123456') as ciphertext;
+------------------------+
| ciphertext             |
+------------------------+
| 0x24E9E4966469         |
+------------------------+
1 row in set (0.00 sec)
```

## decrypt {#decrypt}

This function decrypts ciphertext into a plaintext using these modes:

- aes-128-ecb, aes-192-ecb, aes-256-ecb
- aes-128-cbc, aes-192-cbc, aes-256-cbc
- aes-128-ofb, aes-192-ofb, aes-256-ofb
- aes-128-gcm, aes-192-gcm, aes-256-gcm
- aes-128-ctr, aes-192-ctr, aes-256-ctr
- aes-128-cfb, aes-128-cfb1, aes-128-cfb8

**Syntax**

```sql
decrypt('mode', 'ciphertext', 'key' [, iv, aad])
```

**Arguments**

- `mode` — Decryption mode. [String](/sql-reference/data-types/string).
- `ciphertext` — Encrypted text that needs to be decrypted. [String](/sql-reference/data-types/string).
- `key` — Decryption key. [String](/sql-reference/data-types/string).
- `iv` — Initialization vector. Required for `-gcm` modes, Optional for others. [String](/sql-reference/data-types/string).
- `aad` — Additional authenticated data. Won't decrypt if this value is incorrect. Works only in `-gcm` modes, for others would throw an exception. [String](/sql-reference/data-types/string).

**Returned value**

- Decrypted String. [String](/sql-reference/data-types/string).

**Examples**

Re-using table from [encrypt](#encrypt).

Query:

```sql
SELECT comment, hex(secret) FROM encryption_test;
```

Result:

```text
┌─comment──────────────┬─hex(secret)──────────────────────────────────┐
│ aes-256-gcm          │ A8A3CCBC6426CFEEB60E4EAE03D3E94204C1B09E0254 │
│ aes-256-gcm with AAD │ A8A3CCBC6426D9A1017A0A932322F1852260A4AD6837 │
└──────────────────────┴──────────────────────────────────────────────┘
┌─comment──────────────────────────┬─hex(secret)──────────────────────┐
│ aes-256-ofb no IV                │ B4972BDC4459                     │
│ aes-256-ofb no IV, different key │ 2FF57C092DC9                     │
│ aes-256-ofb with IV              │ 5E6CB398F653                     │
│ aes-256-cbc no IV                │ 1BC0629A92450D9E73A00E7D02CF4142 │
└──────────────────────────────────┴──────────────────────────────────┘
```

Now let's try to decrypt all that data.

Query:

```sql
SELECT comment, decrypt('aes-256-cfb128', secret, '12345678910121314151617181920212') AS plaintext FROM encryption_test
```

Result:

```text
┌─comment──────────────┬─plaintext──┐
│ aes-256-gcm          │ OQ�E
                             �t�7T�\���\�   │
│ aes-256-gcm with AAD │ OQ�E
                             �\��si����;�o�� │
└──────────────────────┴────────────┘
┌─comment──────────────────────────┬─plaintext─┐
│ aes-256-ofb no IV                │ Secret    │
│ aes-256-ofb no IV, different key │ �4�
                                        �         │
│ aes-256-ofb with IV              │ ���6�~        │
 │aes-256-cbc no IV                │ �2*4�h3c�4w��@
└──────────────────────────────────┴───────────┘
```

Notice how only a portion of the data was properly decrypted, and the rest is gibberish since either `mode`, `key`, or `iv` were different upon encryption.

## tryDecrypt {#trydecrypt}

Similar to `decrypt`, but returns NULL if decryption fails because of using the wrong key.

**Examples**

Let's create a table where `user_id` is the unique user id, `encrypted` is an encrypted string field, `iv` is an initial vector for decrypt/encrypt. Assume that users know their id and the key to decrypt the encrypted field:

```sql
CREATE TABLE decrypt_null (
  dt DateTime,
  user_id UInt32,
  encrypted String,
  iv String
) ENGINE = Memory;
```

Insert some data:

```sql
INSERT INTO decrypt_null VALUES
    ('2022-08-02 00:00:00', 1, encrypt('aes-256-gcm', 'value1', 'keykeykeykeykeykeykeykeykeykey01', 'iv1'), 'iv1'),
    ('2022-09-02 00:00:00', 2, encrypt('aes-256-gcm', 'value2', 'keykeykeykeykeykeykeykeykeykey02', 'iv2'), 'iv2'),
    ('2022-09-02 00:00:01', 3, encrypt('aes-256-gcm', 'value3', 'keykeykeykeykeykeykeykeykeykey03', 'iv3'), 'iv3');
```

Query:

```sql
SELECT
    dt,
    user_id,
    tryDecrypt('aes-256-gcm', encrypted, 'keykeykeykeykeykeykeykeykeykey02', iv) AS value
FROM decrypt_null
ORDER BY user_id ASC
```

Result:

```response
┌──────────────────dt─┬─user_id─┬─value──┐
│ 2022-08-02 00:00:00 │       1 │ ᴺᵁᴸᴸ   │
│ 2022-09-02 00:00:00 │       2 │ value2 │
│ 2022-09-02 00:00:01 │       3 │ ᴺᵁᴸᴸ   │
└─────────────────────┴─────────┴────────┘
```

## aes_decrypt_mysql {#aes_decrypt_mysql}

Compatible with mysql encryption and decrypts data encrypted with [AES_ENCRYPT](https://dev.mysql.com/doc/refman/8.0/en/encryption-functions.html#function_aes-encrypt) function.

Will produce same plaintext as `decrypt` on equal inputs. But when `key` or `iv` are longer than they should normally be, `aes_decrypt_mysql` will stick to what MySQL's `aes_decrypt` does: 'fold' `key` and ignore excess bits of `IV`.

Supported decryption modes:

- aes-128-ecb, aes-192-ecb, aes-256-ecb
- aes-128-cbc, aes-192-cbc, aes-256-cbc
- aes-128-cfb128
- aes-128-ofb, aes-192-ofb, aes-256-ofb

**Syntax**

```sql
aes_decrypt_mysql('mode', 'ciphertext', 'key' [, iv])
```

**Arguments**

- `mode` — Decryption mode. [String](/sql-reference/data-types/string).
- `ciphertext` — Encrypted text that needs to be decrypted. [String](/sql-reference/data-types/string).
- `key` — Decryption key. [String](/sql-reference/data-types/string).
- `iv` — Initialization vector. Optional. [String](/sql-reference/data-types/string).

**Returned value**

- Decrypted String. [String](/sql-reference/data-types/string).

**Examples**

Let's decrypt data we've previously encrypted with MySQL:

```sql
mysql> SET  block_encryption_mode='aes-256-ofb';
Query OK, 0 rows affected (0.00 sec)

mysql> SELECT aes_encrypt('Secret', '123456789101213141516171819202122', 'iviviviviviviviv123456') as ciphertext;
+------------------------+
| ciphertext             |
+------------------------+
| 0x24E9E4966469         |
+------------------------+
1 row in set (0.00 sec)
```

Query:

```sql
SELECT aes_decrypt_mysql('aes-256-ofb', unhex('24E9E4966469'), '123456789101213141516171819202122', 'iviviviviviviviv123456') AS plaintext
```

Result:

```text
┌─plaintext─┐
│ Secret    │
└───────────┘
```

<!-- 
The inner content of the tags below are replaced at doc framework build time with 
docs generated from system.functions. Please do not modify or remove the tags.
See: https://github.com/ClickHouse/clickhouse-docs/blob/main/contribute/autogenerated-documentation-from-source.md
-->

<!--AUTOGENERATED_START-->
<!--AUTOGENERATED_END-->
