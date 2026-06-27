import path from "node:path";
import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { RouteError } from "@src/common/utils/route-errors";
import BaseRouter from "@src/routes/apiRouter";
import express, {
	type NextFunction,
	type Request,
	type Response,
} from "express";
import helmet from "helmet";
import logger from "jet-logger";
import morgan from "morgan";
import env from "./common/constants/env";
import Paths from "./common/constants/Paths";

/******************************************************************************
                                Setup
******************************************************************************/

const app = express();

// **** Middleware **** //

// Basic middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Show routes called in console during development
if (env.NODE_ENV === "development") {
	app.use(morgan("dev"));
}

// Security
if (env.NODE_ENV === "production") {
	// eslint-disable-next-line no-process-env
	if (!env.DISABLE_HELMET) {
		app.use(helmet());
	}
}

// Add APIs, must be after middleware
app.use(Paths._, BaseRouter);

// Add error handler
app.use((err: Error, _: Request, res: Response, next: NextFunction) => {
	if (env.NODE_ENV !== "development") {
		logger.err(err, true);
	}
	let status: HttpStatusCodes = HttpStatusCodes.BAD_REQUEST;
	if (err instanceof RouteError) {
		status = err.status;
		res.status(status).json({ error: err.message });
	}
	return next(err);
});

// **** FrontEnd Content **** //

// Set views directory (html)
const viewsDir = path.join(__dirname, "views");
app.set("views", viewsDir);

// Set static directory (js and css).
const staticDir = path.join(__dirname, "public");
app.use(express.static(staticDir));

// Nav to users pg by default
app.get("/", (_: Request, res: Response) => {
	return res.redirect("/users");
});

// Redirect to login if not logged in.
app.get("/users", (_: Request, res: Response) => {
	return res.sendFile("users.html", { root: viewsDir });
});

/******************************************************************************
                                Export default
******************************************************************************/

export default app;
