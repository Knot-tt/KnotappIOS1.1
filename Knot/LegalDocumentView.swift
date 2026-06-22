import SwiftUI

enum LegalDocumentKind {
    case privacy
    case terms

    var title: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .terms:   return "Terms & Conditions"
        }
    }

    var content: String {
        switch self {
        case .privacy: return LegalDocuments.privacyPolicy
        case .terms:   return LegalDocuments.termsAndConditions
        }
    }

    var websiteURL: URL {
        switch self {
        case .privacy: return URL(string: "https://joinknot.app/privacy")!
        case .terms:   return URL(string: "https://joinknot.app/terms")!
        }
    }
}

struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Link(destination: kind.websiteURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "safari")
                        Text(kind.websiteURL.absoluteString)
                            .underline()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color.knotAccent)
                }

                Text(kind.content)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Document Content

enum LegalDocuments {

    static let privacyPolicy: String = """
PRIVACY POLICY
Last updated: 9 June 2026

1. Who We Are

Knot is operated by Meenakshi Sharma (operating as Knot: Tied Together), based in Singapore. When this policy says "Knot", "we", "us", or "our", it refers to Meenakshi Sharma.

Knot is subject to Singapore's Personal Data Protection Act 2012 (PDPA), administered by the Personal Data Protection Commission (PDPC). We have designated a Data Protection Officer (DPO) responsible for our compliance with the PDPA. You can reach the DPO at joinknot.app@gmail.com.

2. What We Collect

We collect only what we need to make Knot work:

• Account information — your name, email address, and profile photo when you sign up.
• Content you create — the groups you join, posts, marketplace listings, RSVPs, and messages you send through Knot.
• Device & usage data — device type, operating system version, app version, and how you use the app, for debugging, performance, and improving features.

We do not collect advertising IDs or national identification numbers (NRIC/FIN), and we do not build advertising profiles or sell your data. Knot does not process payments — any transactions between users happen directly between them, by their own means, and we don't collect or store payment or card details.

If you give us personal data about another person (for example, when reporting a user or sharing contact information), you confirm you have their consent or are otherwise authorised under the PDPA to share it with us.

3. How We Use Your Data

Your data is used to:
• Create and manage your Knot account
• Show you relevant local groups, meetups, and marketplace listings
• Send you notifications you've opted into (RSVPs, messages, group updates)
• Improve the app through anonymous, aggregated analytics
• Prevent abuse and fraud, and keep the community safe
• Comply with our legal obligations

We never sell your personal data or use it for third-party advertising. We won't use your data for any purpose beyond this policy without telling you and, where the PDPA requires it, getting your consent. We take reasonable steps to keep the data we hold accurate, especially before using it to make a decision that affects you.

4. Consent & Legal Basis (PDPA)

Under the PDPA, consent is our main basis for handling your personal data. By creating an account and using Knot, you consent to the collection and use of your data as described in this policy.

In some cases the PDPA lets us handle data without separate consent, including:
• Where it's reasonably necessary to provide a service you've asked for — for example, creating your account or processing a payment you start (known as deemed consent by contractual necessity).
• Legitimate interests — such as keeping the platform secure and preventing fraud, where this doesn't unfairly affect you.
• Where required or authorised by Singapore law, or by a valid legal process.
• To prevent or detect a crime, or protect someone's safety.

You can withdraw consent at any time by emailing joinknot.app@gmail.com. Withdrawing may affect your ability to use parts of Knot — we'll explain the likely consequences when you ask. Withdrawal doesn't affect anything we did lawfully before then.

5. Sharing Your Data

We share data only in these limited cases:
• With other users — your public profile (name, photo, groups) is visible to other Knot users in your area.
• Service providers — Supabase hosts our database, authentication, and storage. They handle data only to provide these services to us, under data processing agreements that require them to protect your data to a standard comparable to the PDPA.
• Legal requirements — if required by law or to protect the safety of our users.
• Business transfers — if Knot is acquired, your data may transfer to the new owner under equivalent privacy protections.

Some of these providers store data on servers outside Singapore (for example, Supabase servers located in Japan). When data is transferred overseas, we make sure it stays protected to a standard comparable to the PDPA, through contractual data processing agreements and the providers' own compliance commitments.

6. Data Retention & Account Deletion

You can delete your account at any time directly in the app, under Profile → Settings → Delete Account.

When you delete your account, we delete or anonymise your personal data within 30 days — except where we're required to keep certain records by law (for example, to investigate abuse or fraud, or to meet a legal obligation). We otherwise keep personal data only for as long as needed to provide Knot or to meet a legal obligation.

7. Your Rights

Under the PDPA, you have the right to:
• Access the personal data we hold about you
• Correct inaccurate or incomplete data
• Request deletion of your data
• Request a copy of your data, which we'll provide in a common, machine-readable format where practicable
• Withdraw consent at any time (where we rely on consent)
• Opt out of non-essential communications at any time
• Lodge a complaint with the PDPC at www.pdpc.gov.sg if you believe your data has been handled in breach of the PDPA

To exercise any of these, email joinknot.app@gmail.com from your registered account email with a description of your request. We may verify your identity first, and we'll respond within 30 days. If we're legally allowed to decline a request, we'll explain why. Please also keep your own information up to date via Profile → Settings.

8. Cookies & Tracking

Knot uses only minimal, essential cookies — for authentication and security. We do not use advertising cookies or third-party tracking pixels in the app or on our website.

9. Children's Privacy

Knot is intended for users aged 17 and above, because it includes in-person meetups and user-generated content. We do not knowingly collect personal data from anyone under 17, and if we learn that we have, we'll delete it promptly.

Users who are 17 (and so under 18) should use Knot only with the consent of a parent or legal guardian, who is responsible for supervising their use and ensuring they understand this policy. We write this policy in plain language so younger users can understand it.

10. Safety & User Content

Knot lets users post content, message each other, and meet in person. To keep the community safe, the app includes tools to report content or users, block abusive users, and filter objectionable content. We review reports and act on them, which may include removing content or suspending accounts.

To report a safety concern or abuse, use the in-app report tools or email us at joinknot.app@gmail.com. Always take sensible precautions when meeting people in person.

11. Security & Breach Notification

We use industry-standard security measures, including encryption in transit (TLS) and at rest. No system is ever completely secure, but we work to protect your data. If you find a security vulnerability, please report it to joinknot.app@gmail.com.

If a data breach occurs that is notifiable under the PDPA, we'll notify the PDPC no later than 3 calendar days after assessing that the breach is notifiable, and we'll notify affected users as soon as practicable where required.

12. Third-Party Links

Knot may contain links to third-party websites or services (for example, resources shared by users). We don't control these and aren't responsible for their content or privacy practices. Review their privacy policies before sharing personal data with them.

13. Changes to This Policy

We may update this policy as Knot grows. When we make significant changes, we'll notify you through the app or by email. The "last updated" date at the top reflects the current version.

14. Contact & Data Protection Officer

Questions or concerns about your personal data? Contact our designated Data Protection Officer (DPO):

Data Protection Officer (DPO)
Meenakshi Sharma (operating as Knot: Tied Together)
Singapore
joinknot.app@gmail.com
Monitored during Singapore business hours (SGT, UTC+8).

We respond to all enquiries within 30 days. If you're not satisfied with our response, you can lodge a complaint directly with the Personal Data Protection Commission (PDPC) at www.pdpc.gov.sg.
"""

    static let termsAndConditions: String = """
TERMS & CONDITIONS
Effective & Last Updated: 9 June 2026

1. About Knot

Knot: Tied Together is a community platform operated by Meenakshi Sharma (Singapore). The app helps people find local groups, connect with their community, and trade with neighbours — all in person, with no online payments.

By creating an account or using the app, you agree to be bound by these Terms and our Privacy Policy.

2. Eligibility

You must be at least 17 years old to use Knot. By using the app, you confirm that you meet this requirement.

You, or the parent or guardian who provided consent, must have the legal capacity to enter into a binding agreement, must not have been previously banned from the app, and your use must comply with the laws of Singapore and/or your country of residence.

Under Singapore's Age of Majority Act (Cap 7), the age of majority is 18. Users aged 17 may use Knot only with explicit parental or guardian permission. Parents and legal guardians accept full responsibility for all obligations under these Terms on behalf of users under 18, including any indemnification and liability obligations. Contractual rights against users under 18 may be limited by the Minors' Contracts Act (Cap 389).

3. Your Account

You are responsible for:
• Keeping your account credentials secure
• All activity that occurs under your account
• Providing accurate and truthful information in your profile

You may not share your account or create multiple accounts to evade restrictions or impersonate others. If you believe your account has been compromised, contact us immediately at joinknot.app@gmail.com.

4. Community Rules

Knot exists to make real life better. To keep it that way, you agree not to:
• Post content that is illegal, abusive, threatening, hateful, sexually explicit, or discriminatory
• Harass, bully, stalk, interact inappropriately with, or harm minors or other users in any way
• Create fake accounts, catfish, impersonate another person, or misrepresent your age, identity, or affiliations
• Engage in spam, fraud, scams, phishing, or deceptive conduct
• Use the app to distribute malware or conduct phishing
• Scrape, decompile, reverse-engineer, or redistribute Knot's content without permission
• Circumvent, disable, or interfere with security features or rate limits
• Violate any applicable local, national, or international law

We reserve the right to remove content or suspend accounts that violate these rules, at our discretion. We may investigate reports of misconduct, remove content, suspend, or permanently ban users, and cooperate with law enforcement where appropriate. Our decisions regarding moderation are final.

5. Knots (Community Groups)

Any user may create a Knot (community group). As a creator or co-admin, you are responsible for the content posted within your Knot and for moderating your members appropriately.

• Knots may be public (open to all) or approval-required (members must be accepted by an admin)
• Creators may charge a membership fee for paid Knots (such as classes or activities) — all such fees are collected by the creators at their discretion and with mutual consent from the members, in cash or another medium acceptable to the members. Knot charges no platform fee.
• Creators are solely responsible for the activities, events, and conduct of their Knot members
• Knot does not organise, supervise, endorse, or guarantee the safety of any group activity or event

We reserve the right to remove any Knot that violates these Terms or is used to organise illegal activity.

6. Messages & Your Content

You retain ownership of any content you post on Knot (photos, descriptions, messages, listings). By posting, you grant Knot a non-exclusive, royalty-free licence to host, store, transmit, and display that content solely to operate the app.

• Messages in direct chats are visible only to the participants
• Messages in group Knot chats are visible to all members of that Knot
• Knot may use automated systems and other technologies, including artificial intelligence, to detect spam, fraud, abuse, safety risks, or violations of these Terms

You confirm that any content you post does not infringe the rights of any third party.

We may remove content that violates these Terms without notice. You may block or report any user at any time from their profile.

Your feedback is welcome. By submitting feedback, suggestions, ideas, or feature requests, you grant Knot a perpetual, worldwide, royalty-free right to use and implement such feedback without compensation or attribution.

If, through your use of Knot, you receive personal data belonging to another user (such as their name, contact details, or address in connection with a transaction), you agree to use it solely for the purpose of that transaction, to comply with all applicable personal data protection laws including Singapore's PDPA, and not to store, share, or transfer it to any third party without that person's consent.

7. Marketplace (Hub)

Knot's Hub allows users to list and exchange goods and services locally:
• All transactions are conducted by mutual agreement between the parties — in cash, or another medium acceptable to both parties, at a mutually agreed meetup location. Knot does not process or hold any payments or arrange meetups.
• Knot is a platform connecting buyers and sellers — we are not a party to any transaction.
• We do not verify the identity of buyers or sellers, nor the ownership, authenticity, condition, safety, legality, or quality of any goods or services listed on the platform.
• We do not guarantee the quality, safety, or legality of any listed item or service.
• Knot charges no commission, transaction fee, or service fee on any sale.
• You are solely responsible for your own transactions, safety, and tax obligations.

By listing an item on the Hub, you warrant that: (a) you are the owner of the item or are authorised to sell it; (b) the item is not stolen, counterfeit, or subject to any third-party ownership or intellectual property claim; (c) your listing description is accurate, complete, and not misleading; and (d) the sale complies with all applicable Singapore laws, including the Consumer Protection (Fair Trading) Act (Cap 52A) and the Sale of Goods Act (Cap 393).

Prohibited listings include: illegal goods or services, weapons, counterfeit or stolen goods, live animals, controlled substances, pornographic material, IP-infringing goods, and anything restricted under Singapore law.

Nothing in these Terms limits or excludes any statutory rights you may have as a buyer under Singapore's Consumer Protection (Fair Trading) Act or Sale of Goods Act that cannot be waived by agreement.

Sellers may mark listings as recurring, meaning they remain visible after a sale. You are responsible for keeping recurring listings accurate and available.

8. Meetups & In-Person Safety

Knot facilitates connections between people, including in-person meetups for marketplace orders and community events. You acknowledge that:
• You attend meetups and arrange transactions entirely at your own risk
• Knot does not conduct background checks, identity verification, criminal screening, or safety assessments of users
• Knot is not responsible for anything that occurs during in-person meetings arranged through the platform
• Users are responsible for exercising good judgement when meeting others
• Parents and guardians are responsible for supervising minors who use the platform

We recommend meeting in public places and bringing a companion.

If you encounter unsafe behaviour, please report it to us immediately at joinknot.app@gmail.com.

9. Fees

The app is free to download and use. Knot does not charge any platform fee, subscription fee, or transaction fee for any current feature. If we introduce fees in the future, we will give at least 30 days' advance notice within the app.

10. Intellectual Property

The Knot name, logo, and app design are owned by Meenakshi Sharma. You may not use our branding without written permission. Nothing in these Terms transfers any intellectual property rights to you.

You are granted a limited, non-exclusive, non-transferable, revocable licence to use the app on your personal device(s) for personal, non-commercial purposes only.

For copyright infringement claims, send a written notice to joinknot.app@gmail.com.

11. Availability & Changes

We aim to keep Knot running smoothly but cannot guarantee 100% uptime. We do not guarantee that any content, messages, listings, or user data will be backed up, preserved, or recoverable. Users are responsible for maintaining their own copies of important information.

We may update, pause, or discontinue any feature at any time. We'll try to give notice of significant changes.

We may also update these Terms from time to time. If we make material changes, we will notify you via push notification or in-app notice at least 14 days before the change takes effect. Continued use of Knot after changes means you accept the updated terms.

No online activity is completely secure. While we take reasonable measures to protect the platform and your information, we cannot guarantee protection against unauthorised access, hacking, malware, or data breaches.

Knot is provided on an "as is" and "as available" basis. To the maximum extent permitted by applicable Singapore law, we disclaim all implied warranties, including any implied warranty of merchantability, fitness for a particular purpose, or non-infringement of third-party rights.

12. Termination

You may delete your account at any time via Profile → Settings → Delete Account, or by emailing joinknot.app@gmail.com. Deletion takes effect within 30 days.

We may suspend or permanently terminate your account without prior notice for violations of these Terms, fraudulent or harmful conduct, or as required by law.

You acknowledge that upon account deletion or termination, all content associated with your account may be permanently deleted. It is your responsibility to retain copies of any important information before deleting your account.

13. Limitation of Liability

To the maximum extent permitted by law, Meenakshi Sharma is not liable for:
• Any indirect, incidental, or consequential damages arising from use of Knot
• Content posted by other users
• Outcomes of in-person meetups or marketplace transactions
• Personal injury or financial loss arising from meetings arranged through the app
• Loss of data or service interruptions
• Any fraud, deception, theft, misconduct, or criminal acts committed by users or third parties

To the maximum extent permitted by applicable Singapore law, including the Unfair Contract Terms Act (Cap 396), Meenakshi Sharma's total aggregate liability to you for any claim arising from your use of Knot will not exceed the maximum amount permitted by law.

Nothing in these Terms limits or excludes liability for: (a) death or personal injury caused by our negligence; (b) fraud or fraudulent misrepresentation; or (c) any other liability that cannot lawfully be limited or excluded under applicable Singapore law.

14. Indemnification

To the extent permitted by applicable Singapore law, you agree to defend, indemnify, and hold harmless Meenakshi Sharma from any claims, damages, losses, liabilities, costs, and expenses (including reasonable legal fees) arising from: your use of the app; your violation of these Terms; your violation of any third-party right; any content you post; or any in-person meeting or transaction you arrange using the app.

15. Governing Law

These Terms are governed by the laws of the Republic of Singapore. Before initiating legal proceedings, you agree to contact us in good faith for at least 30 days to attempt resolution.

For disputes involving claims of SGD 10,000 or less, either party may bring the claim directly in the Singapore Small Claims Tribunal without first attempting mediation or arbitration.

For all other disputes, both parties agree to first attempt mediation or arbitration in Singapore in accordance with the Arbitration Rules of the Singapore International Arbitration Centre (SIAC). Any unresolved disputes will be subject to the exclusive jurisdiction of the courts of Singapore.

All claims must be brought individually, not as a class action.

16. Apple App Store

If you downloaded the app from the Apple App Store, the following also applies:
• These Terms are between you and Meenakshi Sharma only — not Apple Inc.
• Apple has no obligation to provide maintenance or support for the app
• Apple is not responsible for product liability, consumer-protection, or IP infringement claims relating to the app
• Apple is a third-party beneficiary of these Terms and may enforce them against you

17. Miscellaneous

Severability. If any provision of these Terms is found to be unenforceable or invalid, it will be modified to the minimum extent necessary to make it enforceable. All remaining provisions will continue in full force and effect.

Entire Agreement. These Terms, together with our Privacy Policy, constitute the entire agreement between you and Meenakshi Sharma regarding your use of Knot and supersede all prior agreements or understandings on the same subject matter.

No Waiver. Any failure by us to enforce a right or provision of these Terms does not constitute a waiver of that right or provision. We reserve the right to enforce these Terms at any time.

No Assignment. You may not assign or transfer your rights or obligations under these Terms without our prior written consent. We may assign our rights and obligations without restriction.

Relationship of Parties. You and Meenakshi Sharma are independent parties. Nothing in these Terms creates any agency, partnership, joint venture, or employment relationship between us.

18. Contact

Questions about these Terms?

Meenakshi Sharma (operating as Knot: Tied Together)
Singapore
joinknot.app@gmail.com

We will respond to all enquiries within 30 days.
"""
}
