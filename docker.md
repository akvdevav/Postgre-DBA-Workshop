avannala@Q2HWTCX6H4 ~ % docker login dhi.io
Username: arulvkhanna
Password:

WARNING! Your credentials are stored unencrypted in '/Users/avannala/.docker/config.json'.
Configure a credential helper to remove this warning. See
https://docs.docker.com/go/credential-store/

Login Succeeded
avannala@Q2HWTCX6H4 ~ %
avannala@Q2HWTCX6H4 ~ % podman run -d --name etcd \
  --network pg-arena \
  -e ALLOW_NONE_AUTHENTICATION=yes \
  dhi.io/etcd:3-debian-dev
Trying to pull dhi.io/etcd:3-debian-dev...
Getting image source signatures
Copying blob sha256:60c56d9099dd544e941067403ff2d55716044b5be75f27f3f1014bc949dfea7f
Copying blob sha256:483a51cd8535bfa9c386f32265fbb21d33a53ca594fedaf283a5243b5037c6b7
Copying blob sha256:fed4cbe32c46ea8b96720d55f338e23d6a9d279a1158d8b0c054c0695a185d50
Copying blob sha256:da6d90386493628b7eb2e2b94b16867162893f784927dd8eeed1cbc92b8f1e22
Copying blob sha256:0d8bdc017cc145aab50ae927c6c855e8421b9ce4e3e9d4344d391d162ad7969b
Copying blob sha256:5d39acccfcc9aea118b8506bdeaf4f25829ffdc4f84b410d6b1492ed844f1c22
Copying blob sha256:869efe9aad0858713689e76b277c2fd4182d9b4d9e336c15f0070f976c3ee4ed
Copying blob sha256:8f494f80bf5a415506ef4a8335e733e4117d34ed027255cf949664c19fc40411
Copying config sha256:1a67594cd5eb0c559a3d8f5926ad0f23691707e55a090b41a03428a286ed3c20
Writing manifest to image destination
fe9326aeb66d40e0672d2803feb1ac95ab8a3339f4f1b2782b352918fd3a22b3
avannala@Q2HWTCX6H4 ~ %