---
title: "JSON Web Signatures on Node.js"
date: '2013-10-09'
description:
categories:
tags: []
---

My [previous article](/rssssa-pss-and-rsaes-oaep-in-javascript) was really
just a pointer to some enhancements I made to Kenji Urushima's [jsjws](http://kjur.github.io/jsjws/) project. __jsjws__ is an implementation of [JSON Web Signatures](http://tools.ietf.org/html/draft-ietf-jose-json-web-signature-13) (JWS) in Javascript.

Although an excellent library, __jsjws__ as it stands isn't usable on Node.js
for the following reasons:

- It uses pure Javascript crypto routines which are slower that those provided by Node.js modules.
- It uses some global functions which are provided by browsers.
- It isn't packaged up as Node.js module.

This article describes:

- Enhancements I made to __jsjws__ to make it run much faster on Node.js.
- A module, [node-jsjws](https://github.com/davedoesdev/node-jsjws) which you can use in your Node.js projects.
- Extensions I made to __jsjws__ to support [JSON Web Tokens](http://self-issued.info/docs/draft-ietf-oauth-json-web-token.html).

# About JSON Web Signatures

A JSON Web Signature (JWS) is a standard format for representing JSON data.
It has three parts:

<dl>
<dt>Header</dt>
<dd>Metadata such as the algorithm used to generate the signature</dd>

<dt>Payload</dt>
<dd>The data itself</dd>

<dt>Signature</dt>
<dd>A cryptographic signature derived from the header and payload</dd>
</dl>

__jsjws__ supports the following signature algorithms:

<dl>
<dt><a href="http://tools.ietf.org/html/draft-ietf-jose-json-web-algorithms-13#section-3.3">RS256, RS512</a></dt>
<dd>These use RSASSA-PKCS1-V1_5 and SHA-256 or SHA-512 to generate the signature.</dd>

<dt><a href="http://tools.ietf.org/html/draft-ietf-jose-json-web-algorithms-13#section-3.5">PS256, PS512</a></dt>
<dd>These use RSASSA-PSS and SHA-256 or SHA-512 to generate the signature. I'd previously added PSS support <a href="/rsassa-pss-in-node-js">to ursa</a> (a Node.js interface to OpenSSL) and <a href="/rssssa-pss-and-rsaes-oaep-in-javascript">to jsjws</a>.</dd>

<dt><a href="http://tools.ietf.org/html/draft-ietf-jose-json-web-algorithms-14#section-3.2">HS256, HS512</a></dt>
<dd>These use HMAC and SHA-256 or SHA-512 to generate the signature.

<dt><a href="http://tools.ietf.org/html/draft-ietf-jose-json-web-algorithms-14#section-3.6">none</a></dt>
<dd>An empty string is used as the signature.</dd>
</dl>

## Example

Say we have the following JSON payload data:

```json
{"iss":"joe",
 "exp":1300819380,
 "http://example.com/is_root":true}
```

and we want to use __HS256__ to generate a JSON Web Signature.

First we make the header, which is an object with a single property, `alg`, specifying the algorithm we're using. Here's the JSON representation:

```json
{"alg":"HS256"}
```

Next we encode the header and payload as [URL-safe Base 64](http://tools.ietf.org/html/rfc4648#section-5) (base64url). So in our example, the base64url encoding of the header is:

<pre><span class="nocode">eyJhbGciOiJIUzI1NiJ9</span></pre>

and the base64url encoding of the payload is:

<pre><span class="nocode">eyJpc3MiOiJqb2UiLCJleHAiOjEzMDA4MTkzODAsImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ</span></pre>

Now we need to generate a cryptographic signature from the header and payload.
The input to the signature operation is the concatenation of the base64url
header, the character `.` and the base64url payload:

<pre><span class="nocode">eyJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJqb2UiLCJleHAiOjEzMDA4MTkzODAsImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ</span></pre>

In this example, we're using the __HS256__ JWS signature algorithm, which is HMAC with SHA-256 as the digest operation. We feed the signature input (above) as the message to HMAC SHA-256 along with some secret key.

If we choose `foobar` as our secret key then the base64url encoding of the generated cryptographic signature is:

<pre><span class="nocode">74x4aMvBBGj5DPfbi6HEk5RxJuc1lnMlnIlhweidQCw</span></pre>

Finally, the JSON Web Signature is the concatenation of the signature input (i.e.  the base64url header, the character `.` and the base64url payload), the character `.` and the base64url cryptographic signature:

<pre><span class="nocode">eyJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJqb2UiLCJleHAiOjEzMDA4MTkzODAsImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.74x4aMvBBGj5DPfbi6HEk5RxJuc1lnMlnIlhweidQCw</span></pre>

The JWS can be sent to other parties, who can decode the header and payload components and determine its validity by verifying the cryptographic signature component.

# Optimising __jsjws__

__jsjws__ is a great pure Javascript library for generating and verifying
JSON Web Signatures. However, the main use case for JSON Web Signatures on
Node.js is probably asserting identity between different web sites. On busy
sites this might require many JWS operations per second so it's important that
we optimise __jsjws__ in this scenario.

I've modified __jsjws__ to speed it up a bit on Node.js:

- Only parse the header once. __jsjws__ was parsing the header twice: once to
  verify it's a valid JSON string and another to extract data from it.

- Use the built-in `Buffer` class to perform base64 encoding instead of doing it
  in Javascript.

- Use the built-in `crypto` module to hash data instead of doing it in
  Javascript.

- Use the [ursa](https://github.com/Obvious/ursa) module to sign data instead
  of doing it in Javascript. __ursa__ uses OpenSSL to do the heavy lifting.

Kenji Urushima has merged my changes back into __jsjws__ (and its sister project,
[jsrsasign](https://github.com/kjur/jsrsasign)) so it's ready to run on Node.js.

## Introducing [node-jsjws](https://github.com/davedoesdev/node-jsjws)

To make __jsjws__ easier to use on Node.js, I've created a module which you can
use in your projects. It's [available on npm](https://npmjs.org/package/jsjws):

```bash
npm install jsjws
```

Here's an example which generates a private key and then uses it to generate a
JSON Web Signature from some data:

```javascript
var jsjws = require('jsjws');
var key = jsjws.generatePrivateKey(2048, 65537);
var header = { alg: 'PS256' };
var payload = { foo: 'bar', wup: 90 };
var sig = new jsjws.JWS().generateJWSByKey(header, payload, key);
var jws = new jsjws.JWS();
assert(jws.verifyJWSByKey(sig, key));
assert.deepEqual(jws.getParsedHeader(), header);
assert.deepEqual(jws.getParsedPayload(), payload);
```

Use the `JWS` class to generate and verify JSON Web Signatures and access the
header and payload. The full [API is documented](https://github.com/davedoesdev/node-jsjws#api) on the [node-jsjws homepage](https://github.com/davedoesdev/node-jsjws), where the source is available too.

You'll also find a full set of unit tests, including tests for interoperability with [jwcrypto](https://github.com/mozilla/jwcrypto), [python-jws](https://github.com/brianloveswords/python-jws) and __jsjws__ in the browser (using the excellent [PhantomJS](http://phantomjs.org/) headless browser).

## Benchmarks

__node-jsjws__ also comes with a set of benchmarks. Here are some results on a laptop with an Intel Core i5-3210M 2.5Ghz CPU and 6Gb RAM running Ubuntu 13.04.

In the tables, _jsjws-fast_ uses [ursa](https://github.com/Obvious/ursa) ([OpenSSL](http://www.openssl.org/)) for crypto whereas _jsjws-slow_ does everything in Javascript. [jwcrypto](https://github.com/mozilla/jwcrypto) is Mozilla's
implementation of JSON Web Signatures on Node.js.

The algorithm used was __RS256__ because __jwcrypto__ doesn't support __PS256__.

generate_key x10|total (ms)|average (ns)| diff (%)
:--|--:|--:|--:
jwcrypto|1,183|118,263,125|-
jsjws-fast|1,296|129,561,098|10
jsjws-slow|32,090|3,209,012,197|2,613

generate_signature x1,000|total (ms)|average (ns)| diff (%)
:--|--:|--:|--:
jsjws-fast|2,450|2,450,449|-
jwcrypto|4,786|4,786,343|95
jsjws-slow|68,589|68,588,742|2,699

load_key x1,000|total (ms)|average (ns)| diff (%)
:--|--:|--:|--:
jsjws-fast|46|45,996|-
jsjws-slow|232|232,481|405

verify_signature x1,000|total (ms)|average (ns)| diff (%)
:--|--:|--:|--:
jsjws-fast|134|134,032|-
jwcrypto|173|173,194|29
jsjws-slow|1,706|1,705,810|1,173

You can see that in every case, my optimisations make __jsjws__ much faster on
Node.js. It's also faster than __jwcrypto__ for generating and verifying
JSON Web Signatures, but slower for generating keys.

The source to the benchmarks [is available](https://github.com/davedoesdev/node-jsjws/tree/master/bench) from the __node-jsjws__ homepage.

# JSON Web Tokens

[JSON Web Tokens](http://self-issued.info/docs/draft-ietf-oauth-json-web-token.html) are JSON Web Signatures with some well-defined metadata in the header.

I added support for JSON Web Tokens to __node-jsjws__, adding the following
metadata to the header:

<dl>
<dt>exp</dt>
<dd>The expiry date and time of the token</dd>

<dt>nbf</dt>
<dd>The valid-from date and time of the token</dd>

<dt>iat</dt>
<dd>The date and time at which the token was generated</dd>

<dt>jti</dt>
<dd>A unique identifier for the token</dd>
</dl>

Again, the JWT API [is documented](https://github.com/davedoesdev/node-jsjws#json-web-token-functions) on the __node-jsjws__ homepage.

