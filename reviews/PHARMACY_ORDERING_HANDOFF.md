# Pharmacy ordering handoff review

Verified October 16, 2026 against the official pages linked below. This is a curated set of major US chains, not a ranking or an exhaustive pharmacy directory.

## Decision

Use a patient-controlled handoff to an official pharmacy page. Farda does not prefill, submit, or claim that a refill, renewal, transfer, new prescription, price, delivery, or eligibility has been confirmed. No prescription or patient data is placed in a URL. The existing Photon adapter remains optional and unchanged.

The backend exposes:

- `GET /api/pharmacies/directory?query=`: typed directory entries and aliases.
- `POST /api/prescriptions/:prescriptionId/pharmacy-handoff`: authenticated, prescription-owner-only selection of `refill`, `renewal`, `transfer`, or `new_rx`.

Refill and transfer can return an immutable official HTTPS page. Renewal and new-prescription requests return `call_prescriber`; a licensed prescriber must send or renew the prescription. The response contains no medication name, directions, Rx value, patient identity, or pharmacy form values. `copyFields: ["rxNumber"]` tells the client which already-authorized local field it may offer for a deliberate copy action; the API never returns that value.

A phone number is returned only when the owned prescription has a reviewed label, its saved pharmacy name matches the selected chain, and `contactDetails` is exactly an E.164 US number. Generic corporate/support numbers are not substituted.

## Official patient paths

| Pharmacy option | Official evidence and supported handoff |
|---|---|
| CVS Pharmacy | [Refill](https://www.cvs.com/content/refill), [transfer](https://www.cvs.com/content/transfer), and [ordering FAQ](https://www.cvs.com/retail/help/help-subtopic-ordering-your-prescriptions-faqs). CVS says new prescriptions must come from the health care provider or be brought to the store; Farda routes new Rx and renewal to the prescriber. |
| Walgreens | [Pharmacy management](https://www.walgreens.com/topic/pharmacy.jsp) and [guest transfer](https://www.walgreens.com/rx-checkout/guest-transfer-rx). The [developer portal](https://developer.walgreens.com/apis) advertises refill/transfer APIs but also identifies an API key as necessary, so its presence in a public catalog is not treated as production access. |
| Walmart Pharmacy | [Pharmacy](https://www.walmart.com/cp/pharmacy/5431) exposes refill and transfer choices. |
| Costco Pharmacy | [Guest refill](https://rx.costco.com/prescriptions/guestrefill), [warehouse pickup/transfer](https://www.costco.com/pharmacy/warehouse-pickup), and [official help](https://rx.costco.com/help). |
| Kroger | [Kroger Pharmacy](https://www.kroger.com/health/pharmacy) and its [refill FAQ](https://www.kroger.com/health/pharmacy/faqs/refills). Other Kroger-owned banners are not silently matched because shared patient-portal support was not verified. |
| Amazon Pharmacy | [Amazon Pharmacy](https://pharmacy.amazon.com/) and [how it works](https://pharmacy.amazon.com/how-it-works) describe transfers and having a prescriber send a prescription. |
| Publix Pharmacy | [Publix Pharmacy](https://www.publix.com/pharmacy) describes online prescription management; the [pharmacy app page](https://www.publix.com/pharmacy/pharmacy-services/pharmacy-app) describes household management and transfer. |
| Albertsons | [Prescription page](https://www.albertsons.com/pharmacy/prescriptions.html) and [health FAQ](https://www.albertsons.com/pharmacy/health-faqs.html) cover refills and transfers. |
| Safeway | [Prescription page](https://www.safeway.com/pharmacy/prescriptions.html) covers refill and transfer. Albertsons and Safeway remain separate choices so the handoff stays on the brand the user selected. |
| H-E-B | [H-E-B Pharmacy](https://www.heb.com/pharmacy) is the official pharmacy entry point. Because a stable public deep link was not verified, both actions land at that entry point for the patient to choose. |
| Sam's Club | [Sam's Pharmacy](https://www.samsclub.com/health-and-wellness/cp/pharmacy/16670402) describes filling or refilling prescriptions. Both actions land at this official entry point where availability can be reviewed. |
| Meijer | [Meijer Pharmacy](https://www.meijer.com/services/pharmacy.html) is the official entry point. Both actions land there because a stable public action-specific link was not verified. |

CVS's developer catalog was not sufficiently available in search to verify guest-refill API credentials, contractual access, request schema, or production approval. A public catalog listing alone would not justify connecting it. The implemented handoff performs no pharmacy API calls and does not scrape authenticated forms.

## Contract

```json
{
  "data": {
    "pharmacy": { "id": "cvs", "name": "CVS Pharmacy" },
    "purpose": "refill",
    "action": { "mode": "external_site", "url": "https://www.cvs.com/content/refill" },
    "copyFields": ["rxNumber"],
    "notice": "Continue on the pharmacy's official site and review the request there. Farda has not sent or submitted a prescription request."
  }
}
```

The client must compare the returned URL with the selected directory action before opening it. Opening the page is not evidence that a request was accepted. Existing manual refill status remains user-reported.

## Verification

Focused unit coverage checks the allowlisted HTTPS origins, absence of URL query data, alias matching, ownership isolation, omission of prescription details, reviewed/matching phone policy, and prescriber routing. TypeScript production typecheck passes. Live pharmacy forms and orders were intentionally not exercised.
