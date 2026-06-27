require("dotenv").config();
const { betterAuth } = require("better-auth");
const { fromNodeHeaders } = require("better-auth/node");
const { Pool } = require("pg");

// Make sure process.env is populated (e.g. DATABASE_URL)

// Connect to the same Postgres database that your Main TypeScript app uses.
// better-auth natively accepts a pg Pool to operate without an ORM (like Prisma) in this JS submodule.
const auth = betterAuth({
  // Provide the Base URL where this submodule is running.
  // This satisfies Better Auth's requirement for URL generation and origin checks.
  baseURL: process.env.BETTER_AUTH_URL || "http://localhost:5000",
  database: new Pool({
    // Make sure your .env has DATABASE_URL set identically to your main app's .env
    connectionString: process.env.DATABASE_URL
  })
});

const verifyToken = async (req, res, next)  => {
  try {
    // 1. better-auth's `getSession` natively parses headers, cookies, and bearer tokens.
    // It verifies the token directly against the shared PostgreSQL database.
    const session = await auth.api.getSession({
      headers: fromNodeHeaders(req.headers) 
    });

    if (!session || !session.user) {
      return res.status(401).json({ error: "Access Denied: Invalid or missing Better Auth session" });
    }

    console.log("Better Auth session verified successfully:", session.user.id);
    
    // 2. Attach user and session to request object
    req.user_id = session.user.id;
    req.user_role = session.user.role || 'user';
    req.user = session.user;
    req.session = session.session;

    next();
  } catch (error) {
    console.error("Session verification failed", error);
    return res.status(500).json({ error: "Internal Server Error during auth checks" });
  }
};

module.exports = verifyToken;
