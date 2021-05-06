/* eslint-disable prettier/prettier */
/* eslint-disable no-console */
const { OnePasswordConnect } = require("@1password/connect");

const vaultId = process.env.OP_VAULT;
const opToken = process.env.OP_TOKEN;
const opSharedDoc = process.env.OP_SHARED_DOCUMENT;
const opTenantDoc = process.env.OP_TENANT_DOCUMENT;
const sectionLabel = "Secrets";
const serverUrl =
  process.env.CI === "true"
    ? "http://op-connect-api:8080"
    : "http://localhost:8080";

const getPureError = error => {
  return JSON.stringify(error, Object.getOwnPropertyNames(error));
};

function errorAndExit(msg, errorObject) {
  console.log(`print_red '${msg}'`);
  console.log("exit 1");
  if (errorObject) {
    throw errorObject;
  }
  throw new Error(msg);
}

async function getSecrets(op, opTitle, secretType) {
  if (!opTitle) return `${secretType} secret not configured skipping`;

  const secretsRes = await op
    .getItemByTitle(vaultId, opTitle)
    .then(res => {
      if (res.length === 0) {
        errorAndExit(`[ENV ERROR] op "${opTitle}" did not return any secrets`);
      }
      return res;
    })
    .catch(e =>
      errorAndExit(
        `[ENV ERROR] failed to fetch: ${vaultId}, ${opTitle} ${getPureError(
          e
        )}`,
        e
      )
    );

  // Only return secrets in the section defined by "sectionLabel"
  const secretSectionId = secretsRes.sections
    .filter(section => section.label === sectionLabel)
    .map(section => section.id)[0];
  const secretsExport = secretsRes.fields.filter(
    field => field.section && field.section.id === secretSectionId
  );
  if (secretsExport.length === 0) {
    errorAndExit(
      `[ENV ERROR] op "${opSharedDoc}" ${sectionLabel}" section does not contain any values`
    );
  }

  // Return in a format that can be evaluated by bash function
  return secretsExport
    .map(secret => {
      // Enforce bash literals to prevent code injection
      const label = secret.label.replace(/'/g, `'"'"'`);
      const value = secret.value.replace(/'/g, `'"'"'`);
      return `export '${label}'='${value}'`;
    })
    .join("\n");
}

async function main() {
  try {
    const op = OnePasswordConnect({
      serverURL: serverUrl,
      token: opToken
    });

    const sharedSecretPromise = getSecrets(
      op,
      opSharedDoc,
      "OP_SHARED_DOCUMENT"
    );
    const tenantSecretPromise = getSecrets(
      op,
      opTenantDoc,
      "OP_TENANT_DOCUMENT"
    );
    const [sharedSecret, tenantSecret] = await Promise.all([
      sharedSecretPromise,
      tenantSecretPromise
    ]);

    // Log output to be read by bash eval
    console.log(sharedSecret);
    console.log(tenantSecret);
  } catch (e) {
    console.log(`print_red '[ENV ERROR] unexpected crash ${e}'`);
    console.log("exit 1");
  }
}

main();
