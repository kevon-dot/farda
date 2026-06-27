const JWT = require("jsonwebtoken");
const config = require('../config/config');

console.log("\n=== JWT SECRET CHECK ===\n");
console.log("JWT Secret being used:", config.jwt.secret);
console.log("Secret length:", config.jwt.secret.length);

/**
 * Generate a test JWT token for testing API endpoints
 * Run this file: node utils/generateTestToken.js
 */

// Test user data
const testUser = {
  sub: "nc_test3453", // user_id
  role: "user",
};

const testCaregiver = {
  sub: "caregiver_nc", // caregiver_id
  role: "caregiver",
 
};

// Generate tokens
const userToken = JWT.sign(testUser, config.jwt.secret, { 
  expiresIn: config.jwt.expiresIn 
});

const caregiverToken = JWT.sign(testCaregiver, config.jwt.secret, { 
  expiresIn: config.jwt.expiresIn 
});

console.log("\n=== TEST JWT TOKENS ===\n");
console.log("USER TOKEN (role: user):");
console.log(userToken);
console.log("\n");
console.log("CAREGIVER TOKEN (role: caregiver):");
console.log(caregiverToken);
console.log("\n");




