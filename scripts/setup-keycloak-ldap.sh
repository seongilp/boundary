#!/usr/bin/env bash
# Keycloak User Federation: lldap(LDAP)을 boundary realm 에 연결 + 그룹 매퍼 + 동기화.
# (멱등: 이미 있으면 건너뜀)
set -euo pipefail
KC() { docker exec boundary-keycloak /opt/keycloak/bin/kcadm.sh "$@"; }

KC config credentials --server http://localhost:8080 --realm master --user admin --password admin >/dev/null
REALM_ID=$(KC get realms/boundary --fields id | jq -r '.id')

# 이미 lldap provider 있으면 재사용
LDAP_ID=$(KC get components -r boundary -q name=lldap --fields id 2>/dev/null | jq -r '.[0].id // empty')
if [ -z "$LDAP_ID" ]; then
  echo "==> LDAP federation provider 생성"
  LDAP_ID=$(KC create components -r boundary \
    -s name=lldap -s providerId=ldap -s providerType=org.keycloak.storage.UserStorageProvider \
    -s parentId="$REALM_ID" \
    -s 'config.enabled=["true"]' -s 'config.priority=["0"]' -s 'config.vendor=["other"]' \
    -s 'config.editMode=["READ_ONLY"]' -s 'config.importEnabled=["true"]' -s 'config.syncRegistrations=["false"]' \
    -s 'config.connectionUrl=["ldap://lldap:3890"]' \
    -s 'config.bindDn=["uid=admin,ou=people,dc=example,dc=com"]' \
    -s 'config.bindCredential=["adminpassword"]' \
    -s 'config.usersDn=["ou=people,dc=example,dc=com"]' \
    -s 'config.usernameLDAPAttribute=["uid"]' -s 'config.rdnLDAPAttribute=["uid"]' \
    -s 'config.uuidLDAPAttribute=["entryuuid"]' -s 'config.userObjectClasses=["inetOrgPerson"]' \
    -s 'config.searchScope=["1"]' -i)
  echo "==> group-ldap-mapper 생성"
  KC create components -r boundary \
    -s name=group-mapper -s providerId=group-ldap-mapper \
    -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper -s parentId="$LDAP_ID" \
    -s 'config."groups.dn"=["ou=groups,dc=example,dc=com"]' \
    -s 'config."group.name.ldap.attribute"=["cn"]' \
    -s 'config."group.object.classes"=["groupOfNames"]' \
    -s 'config."membership.ldap.attribute"=["member"]' \
    -s 'config."membership.attribute.type"=["DN"]' \
    -s 'config."membership.user.ldap.attribute"=["uid"]' \
    -s 'config.mode=["READ_ONLY"]' \
    -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]' \
    -s 'config."preserve.group.inheritance"=["false"]' -s 'config."groups.path"=["/"]' >/dev/null
fi

echo "==> 전체 동기화"
KC create "user-storage/$LDAP_ID/sync?action=triggerFullSync" -r boundary >/dev/null
echo "✅ federation 완료. Keycloak 사용자:"
KC get users -r boundary --fields username | jq -r '.[].username' | sed 's/^/   /'
