import env from "../common/constants/env";
import { PhotonRefillsProvider } from "./providers/photon";

/** One process-local connector shared by request and reconciliation paths. */
export const photonRefillsProvider = new PhotonRefillsProvider({
	enabled: env.FARDA_REFILL_PROVIDER_ENABLED,
	environment: env.FARDA_REFILL_PROVIDER_ENVIRONMENT,
	clientId: env.PHOTON_CLIENT_ID,
	clientSecret: env.PHOTON_CLIENT_SECRET,
});
