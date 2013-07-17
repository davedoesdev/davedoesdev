---
title: RSSSSA-PSS and RSAES-OAEP in Javascript
date: '2013-07-06'
description: Implementations of RSSSSA-PSS and RSAES-OAEP in Javascript, with some help from giants
categories:
tags: [javascript, crypto, RSA, RSASSA-PSS, RSAES-OAEP, jsjws]
---

[Last time out](/rsassa-pss-in-node-js), I added support for [RSASSA-PSS](http://tools.ietf.org/html/rfc3447#section-8.1) encoded signatures to the [ursa](https://github.com/Obvious/ursa) Node.js module. The code I added exposes the OpenSSL implementation of RSASSA-PSS to Node.js programs. [RFC 3447](http://tools.ietf.org/html/rfc3447) recommends new applications use RSASSA-PSS instead of the older RSASSA-PKCS1-v1_5 scheme.

RFC 3447 also recommends new applications use [RSAES-OAEP](http://tools.ietf.org/html/rfc3447#section-7.1) ciphertext encoding instead of the older RSAES-PKCS1-v1\_5 scheme. __ursa__ already exposes the OpenSSL RSAES-OAEP implementation to Node.js programs.

I've been using Tom Wu's [RSA Javascript library](http://www-cs-students.stanford.edu/~tjw/jsbn/) in a non-Node.js project. Tom's library is pure Javascript (it doesn't wrap native code) and I wanted to contribute something back:

- A Javascript implementation of RSASSA-PSS signature encoding.
- A Javascript implementation of RSAES-OAEP ciphertext encoding.

# RSASSA-PSS in Javascript

I'm really standing on the shoulders of giants here. The [Forge project](https://github.com/digitalbazaar/forge) already has a [PSS implementation](https://github.com/digitalbazaar/forge/blob/master/js/pss.js).

The PSS algorithm relies on hash functions and so the Forge implementation
necessarily relies on other bits of Forge.

The project I'm working on actually uses Tom Wu's RSA library as distributed in
Kenji Urushima's excellent [jsjws](http://kjur.github.io/jsjws/). __jsjws__ implements [JSON Web Signatures](http://tools.ietf.org/html/draft-ietf-jose-json-web-signature-13) (JWS) in pure Javascript. JWS is a standard mechanism and format for signing JSON data. I'll write some more about __jsjws__ in future posts.

So what I ended up doing was to add a PSS implementation to __jsjws__, using
RFC 3447 and the Forge PSS implementation as references. [The code](https://github.com/kjur/jsjws/commit/7e9641b60ac175ceaa736a7b69ffc3d399aef239) isn't too complicated but it's best to read it alongside [the spec](http://tools.ietf.org/html/rfc3447#section-8.1). You'll also need to refer to the [encoding section](http://tools.ietf.org/html/rfc3447#section-9.1) of the spec.

RSASSA-PSS encoding is now merged into __jwjws__ mainline. In a future post I'll describe a simple signing and verification library I wrote which makes it easy to use PSS (and OAEP) for common cases on Node.js or in the browser. I'll also describe some interoperability tests I ran between OpenSSL, Node.js and browser.

# RSAES-OAEP in Javascript

More giants and shoulders here! Ellis Pritchard has [implemented RSAES-OAEP in Javascript](http://webrsa.cvs.sourceforge.net/viewvc/webrsa/Client/RSAES-OAEP.js?content-type=text%2Fplain) and [so has David Madden](https://groups.google.com/forum/#!topic/crypto-js/VotElO00yHc). 

Ellis's implementation is part of [webrsa](http://webrsa.sourceforge.net/) and David's uses [CryptoJS](https://code.google.com/p/crypto-js/).

So again, I used these together with [the RFC](http://tools.ietf.org/html/rfc3447#section-7.1) to help me add OAEP encoding to __jsjws__. [The code](https://github.com/kjur/jsjws/commit/4a2d8958c82100bf0fecfda9933bb399a83b8b14#) has been merged into __jsjws__.

Next time out, I'll describe another enhancement I made to __jsjws__ plus some libraries I derived from it.

