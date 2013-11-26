---
title: A simple and consistent wrapper for Javascript crypto
date: '2013-11-24'
description: 'simple-crypt: A simple and easy-to-use encryption and signing library'
categories:
tags: [javascript, Node.js, crypto, AES-128-CBC, PBKDF2, RSA, HMAC, SHA-256 ]
---

This post is about [simple-crypt](https://github.com/davedoesdev/simple-crypt), a Javascript wrapper library for encrypting and signing data.

Here's what I did and didn't want to do with __simple-crypt__:

- Don't re-implement any cryptographic algorithms.
- Don't get into key exchange protocols.
- Do write extensive unit tests, ideally including some well-known test vectors.
- Do make a consistent API for encrypting and signing data using different types of keys:
    - Symmetric keys
    - Asymmetric keys
    - Password-derived keys
- Do hardcode which encryption and signature algorithms to use:
    - HMAC-SHA-256 for symmetric signing.
    - RSA-SHA-256 with [RSASSA-PSS](http://tools.ietf.org/html/rfc3447#section-8.1) encoding for asymmetric signing.
    - AES-128-CBC for symmetric key encryption.
    - RSA, [RSAES-OAEP](http://tools.ietf.org/html/rfc3447#section-7.1) encoding and AES-128-CBC for asymmetric encryption.
- Do add a checksum before encrypting data.
- Do JSON encode data before encrypting or signing it.
- Do make it easy to disable processing and pass plaintext through instead.
- Do make it easy to add metadata so the recipient knows which key to use.

# Basic usage

Here's what I came up with. Everything revolves around the `Crypt` class. Say you have some `key` (symmetric, public, private or password). Then you'd pass it to `Crypt.make` to make a `Crypt` object like this:

```javascript
Crypt.make(key, function (err, crypt)
{
    // if err exists then handle it
    // otherwise crypt is a Crypt object
});
```

You can then use `crypt` to sign, encrypt, verify or decrypt data. For example, 
using a symmetric key:

```javascript
key = crypto.randomBytes(Crypt.get_key_size());

Crypt.make(key, function (err, crypt)
{
    crypt.sign({ foo: 90 }, function (err, signed)
    {
        // send 'signed' somewhere else
    });
});

// somewhere else (how to get exchange key securely is left to the application)...
Crypt.make(key, function (err, crypt)
{
    crypt.verify(signed, function (err, verified)
    {
        assert.deepEqual(verified, { foo: 90 });
    });
});
```

# Keys

## Symmetric keys

Symmetric keys should be fixed length. On Node.js you might make one like this:

```javascript
var key = crypto.randomBytes(Crypt.get_key_size());
```

## Asymmetric keys

You can pass PEM-encoded RSA public and private keys to `Crypt.make`:

```javascript
var priv_pem = '-----BEGIN RSA PRIVATE KEY-----\nMIIEogIBAAKCAQEA4qiw...Se2gIJ/QJ3YJVQI=\n-----END RSA PRIVATE KEY-----';
var pub_pem = '-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w...BoeoyBrpTuc4egSCpj\nsQIDAQAB\n-----END PUBLIC KEY-----';
```

Use the public key to encrypt and the private key to decrypt:

```javascript
Crypt.make(pub_pem, function (err, crypt)
{
    crypt.encrypt({ bar: 'hi' }, function (err, encrypted)
    {
        // send 'encrypted' somewhere else
    });
});

// somewhere else...
Crypt.make(priv_pem, function (err, crypt)
{
    crypt.decrypt(encrypted, function (err, decrypted)
    {
        assert.deepEqual(decrypted, { bar: 'hi' });
    });
});
```

(the private key can also sign and the public key verify).

## Passwords

You'll need to specify the number of iterations (for PBKDF2) along with the password, for example:

```javascript
var key = { password: 'P@ssW0rd!', iterations: 10000 };
```

# Producing plaintext

I wanted to be able to turn off signing or encryption easily and pass the data through untouched. Here's how:

```javascript
Crypt.make(key, function (err, crypt)
{
    var whether_to_encrypt = false;
    crypt.maybe_encrypt(whether_to_encrypt, 123.456, function (err, encrypted)
    {
        // send 'encrypted' somewhere else...
    });
});

// somewhere else has to call maybe_decrypt...
Crypt.make(key, function (err, crypt)
{
    crypt.maybe_decrypt(encrypted, function (err, decrypted)
    {
        assert.equal(decrypted, 123.456);
    });
});
```

There are `maybe_sign` and `maybe_verify` too.

# Adding metadata

_Unencrypted_ metadata can be added alongside the encrypted payload. Typically the recipient would use it to determine which key to use to decrypt the actual data.

Instead of passing the key to `Crypt.make`, you pass a function to `maybe_encrypt` which supplies the key and metadata:

```javascript
var keys = { super_secret_sensor_29: 'some random key!' };
var data = { device_id: 'super_secret_sensor_29', value: 42 };

Crypt.make().maybe_encrypt(data, function (err, encrypted)
{
    // send 'encrypted' somewhere else
}, function (device_id, cb) // must supply key and metadata to 'cb'
{
    cb(null, keys[device_id], device_id);
}, data.device_id /* any metadata you want to pass into the function */);

// somewhere else...

Crypt.make().maybe_decrypt(encrypted, function (err, decrypted)
{
    assert.deepEqual(decrypted, data);
}, function (cb, device_id) // receives metadata, must supply key to 'cb'
{
    cb(null, keys[device_id]);
});
```

# What __simple-crypt__ does _not_ do

__simple-crypt__ doesn't implement the signing and encryption algorithms itself.

- On Node.js it wraps the [crypto](http://nodejs.org/api/crypto.html) and [ursa](https://github.com/Obvious/ursa) modules. 

- When running in a pure Javascript environment, it wraps  [SlowAES](https://code.google.com/p/slowaes/), [pbkdf2.js](http://anandam.name/pbkdf2/), [CryptoJS](https://code.google.com/p/crypto-js/), [jsrsasign](http://kjur.github.io/jsrsasign/) and [js-rsa-pem](https://bitbucket.org/adrianpasternak/js-rsa-pem/wiki/Home). 

__simple-crypt__ doesn't say anything about how to exchange keys. If you want [Perfect Forward Secrecy](http://en.wikipedia.org/wiki/Forward_secrecy#Perfect_Forward_Secrecy) then you might consider using something like [Diffie-Hellman](http://nodejs.org/api/crypto.html#crypto_crypto_getdiffiehellman_group_name) to exchange symmetric keys. You might also need some kind of public key infrastructure to support your asymmetric keys.

Finally, __simple-crypt__ doesn't get into key derivation. Key derivation algorithms are useful if you intend to use the same key for multiple purposes. __simple-crypt__ expects any key derivation to be done beforehand &mdash; i.e. it expects to be used with the _derived_ key.

The reason for this is that it's impossible to cater for the wide range of ancillary data which might be fed into a key derivation algorithm. For examples of key derivation functions, consider:

- [Recommendation for Key Derivation Using Pseudorandom Functions](http://csrc.nist.gov/publications/nistpubs/800-108/sp800-108.pdf)

- [Recommendation for Key Derivation through Extraction-then-Expansion](http://csrc.nist.gov/publications/nistpubs/800-56C/SP-800-56C.pdf)

- [HMAC-based Extract-and-Expand Key Derivation Function](http://tools.ietf.org/html/rfc5869)

# Where to get it

You can find the __simple-crypt__ source, API documentation and unit tests [here](https://github.com/davedoesdev/simple-crypt).

Please let me know if you have a problem or spot something wrong!

