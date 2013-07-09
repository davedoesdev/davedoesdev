---
title: "RSASSA-PSS in Node.js"
date: '2013-05-04'
description: Exposing RSASSA-PSS and RSASSA-PKCS1 to Node.js programs by modifying the ursa module
categories:
tags: [Node.js, crypto, RSA, RSASSA-PSS, OpenSSL]
---

This post is about encoding schemes for RSA signatures. The Public-Key
Cryptography Standards (PKCS) #1 ([RFC 3447](http://tools.ietf.org/html/rfc3447)) specifies two schemes:

- [RSASSA-PSS](http://tools.ietf.org/html/rfc3447#section-8.1), RSA Signature
  Scheme with Appendix - Probabilistic Signature Scheme.
- [RSASSA-PKCS1-v1_5](http://tools.ietf.org/html/rfc3447#section-8.2)

Basically, PSS is the newer scheme and can optionally include some randomness
in the encoding (though it doesn't rely on it). There are no known attacks
against PKCS1-v1_5 but you have to be more careful when using it. PKCS#1
recommends PSS in new applications:

> Although no attacks are known
> against RSASSA-PKCS1-v1\_5, in the interest of increased robustness,
> RSASSA-PSS is recommended for eventual adoption in new applications.
> RSASSA-PKCS1-v1\_5 is included for compatibility with existing
> applications, and while still appropriate for new applications, a
> gradual transition to RSASSA-PSS is encouraged.

I needed RSA signing for a Node.js project and it seemed sensible to use
RSASSA-PSS since I control both ends of the communication path.

A nice module for doing RSA crypto in Node.js is [ursa](https://github.com/Obvious/ursa). It wraps OpenSSL, which is usually a good thing because you don't have
to do it yourself.

__ursa__ hardcodes the encoding type for signatures to PKCS1-v1\_5 so I had to
modify it to allow applications to choose PSS. [Kris Brown](https://github.com/krisb) has already
done a good job of [modifying ursa](https://github.com/Obvious/ursa/pull/16) so applications can choose the encoding
type for encryption. I forked his version of __ursa__ and did the same for
RSA signing.

Unfortunately, it wasn't as simple as I first thought. OpenSSL's RSA signing
function is __RSA\_private\_encrypt__ and its signature verification function is
__RSA\_public\_decrypt__. They both take a padding (encoding) type as their
last argument:

    int RSA_private_encrypt(int flen, unsigned char *from,
       unsigned char *to, RSA *rsa, int padding);
    
    int RSA_public_decrypt(int flen, unsigned char *from,
       unsigned char *to, RSA *rsa, int padding);

So surely we just specify PSS as the __padding__ argument we pass in?
The answer is no! OpenSSL implements PSS in _separate_ functions,
__RSA\_padding\_add\_PKCS1\_PSS__ and __RSA\_verify\_PKCS1\_PSS__:

    int RSA_padding_add_PKCS1_PSS(RSA *rsa, unsigned char *EM,
       const unsigned char *mHash,
       const EVP_MD *Hash, int sLen)

    int RSA_verify_PKCS1_PSS(RSA *rsa, const unsigned char *mHash,
       const EVP_MD *Hash, const unsigned char *EM, int sLen)

This is because PSS involves hashing some data and so requires us to pass the
hash algorithm you want it to use (__Hash__). RSA is very slow so you usually
only sign a digest of the data (__mHash__ here) rather than the data itself.
Usually you specify the same hash algorithm for __Hash__ that you used to
generate __mHash__.

I added wrappers around __RSA\_padding\_add\_PKCS1\_PSS__ and __RSA\_verify\_PKCS1\_PSS__ to the __ursa__ native C++ code and exported them to Javascript.

Signing data using PSS is then done like this:

1. Hash the data.
2. Call __RSA\_padding\_add\_PKCS1\_PSS__ to encode (pad) the digest.
3. Call __RSA\_private\_encrypt__ with the padded digest and specify __RSA\_NO\_PADDING__ as the __padding__ argument to ensure no more padding is done.

Verifying a signature against some data using PSS is done like this:

1. Call __RSA\_public\_decrypt__ with the signature to retrieve the padded digest.
2. Hash the data.
3. Call __RSA\_verify\_PKCS1\_PSS__ with the digest and the padded digest we
   retrieved from the signature. It returns whether the former after padding
   matches the latter.

I did this in the existing __hashAndSign__ and __hashAndVerify__ functions
of the __ursa__ module. I also exported a constant, __RSA\_PKCS1\_PSS\_PADDING__, 
to specify use of PSS encoding with these functions.

For example, to sign some data using an RSA key you might do something like
this:

    signature = key.hashAndSign('sha256', data, 'base64', 'base64', ursa.RSA_PKCS1_PSS_PADDING);

and to verify the signature:

    key.hashAndVerify('sha256', data, signature, 'base64', ursa.RSA_PKCS1_PSS_PADDING)

I'm assuming __key__ here is an RSA key read by __ursa__ and the data and signature
are both encoded in Base64.

You can find all the __ursa__ changes needed to support PSS in my [pull request](https://github.com/krisb/ursa/pull/1) and [forked repo](https://github.com/davedoesdev/ursa). They also contain some minor cleanups I spotted while
making my changes.

In my next post I'll look at implementing RSASSA-PSS in Javascript without
using OpenSSL. I'll also implement RSAES-OAEP, an encryption scheme specified
in RFC 3447.

