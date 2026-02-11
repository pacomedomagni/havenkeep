import sgMail from '@sendgrid/mail';
import { logger } from '../utils/logger';
import { config } from '../config';

// Initialize SendGrid
if (config.sendgrid.apiKey) {
  sgMail.setApiKey(config.sendgrid.apiKey);
}

export class EmailService {
  /**
   * Send partner gift activation email to homebuyer
   */
  static async sendGiftActivationEmail(data: {
    to: string;
    homebuyer_name: string;
    partner_name: string;
    partner_company?: string;
    premium_months: number;
    activation_url: string;
    activation_code: string;
    custom_message?: string;
    brand_color?: string;
    logo_url?: string;
  }): Promise<void> {
    try {
      const {
        to,
        homebuyer_name,
        partner_name,
        partner_company,
        premium_months,
        activation_url,
        activation_code,
        custom_message,
        brand_color = '#3B82F6',
        logo_url,
      } = data;

      const fromName = partner_company || partner_name;
      const firstName = homebuyer_name.split(' ')[0];

      const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your Closing Gift from ${fromName}</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 40px 20px;">
    <tr>
      <td align="center">
        <!-- Main Container -->
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">

          <!-- Header with Brand Color -->
          <tr>
            <td style="background: linear-gradient(135deg, ${brand_color} 0%, ${brand_color}dd 100%); padding: 40px 40px 30px; text-align: center;">
              ${logo_url ? `<img src="${logo_url}" alt="${fromName}" style="max-height: 60px; margin-bottom: 20px;">` : ''}
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold;">🎁 You've Received a Gift!</h1>
              <p style="color: #ffffff; margin: 10px 0 0; font-size: 16px; opacity: 0.95;">From ${fromName}</p>
            </td>
          </tr>

          <!-- Content -->
          <tr>
            <td style="padding: 40px;">
              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">Hi ${firstName},</p>

              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 30px;">
                Congratulations on your new home! ${fromName} is excited to share a special gift with you: <strong>${premium_months} months of HavenKeep Premium</strong> — completely free!
              </p>

              ${custom_message ? `
              <div style="background-color: ${brand_color}10; border-left: 4px solid ${brand_color}; padding: 20px; margin: 0 0 30px; border-radius: 4px;">
                <p style="color: #374151; font-size: 15px; line-height: 1.6; margin: 0; font-style: italic;">
                  "${custom_message}"
                </p>
              </div>
              ` : ''}

              <!-- What's Included Box -->
              <div style="background-color: #f9fafb; border-radius: 8px; padding: 30px; margin: 0 0 30px;">
                <h2 style="color: #111827; font-size: 20px; margin: 0 0 20px; font-weight: 600;">What's Included</h2>

                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td style="padding: 12px 0;">
                      <span style="color: ${brand_color}; font-size: 24px; margin-right: 12px;">✨</span>
                      <span style="color: #374151; font-size: 15px;"><strong>${premium_months} Months Premium</strong> — Full access to all features</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 12px 0;">
                      <span style="color: ${brand_color}; font-size: 24px; margin-right: 12px;">📦</span>
                      <span style="color: #374151; font-size: 15px;"><strong>Unlimited Items</strong> — Track all your appliances & warranties</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 12px 0;">
                      <span style="color: ${brand_color}; font-size: 24px; margin-right: 12px;">📄</span>
                      <span style="color: #374151; font-size: 15px;"><strong>Unlimited Documents</strong> — Store receipts, manuals & more</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 12px 0;">
                      <span style="color: ${brand_color}; font-size: 24px; margin-right: 12px;">🔔</span>
                      <span style="color: #374151; font-size: 15px;"><strong>Smart Reminders</strong> — Never miss a warranty expiration</span>
                    </td>
                  </tr>
                </table>
              </div>

              <!-- CTA Button -->
              <table width="100%" cellpadding="0" cellspacing="0" style="margin: 0 0 30px;">
                <tr>
                  <td align="center">
                    <a href="${activation_url}" style="display: inline-block; background-color: ${brand_color}; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
                      Activate Your Gift
                    </a>
                  </td>
                </tr>
              </table>

              <!-- Activation Code Box -->
              <div style="background-color: #f9fafb; border: 2px dashed #d1d5db; border-radius: 8px; padding: 20px; text-align: center; margin: 0 0 30px;">
                <p style="color: #6b7280; font-size: 13px; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 0.5px;">Or use activation code</p>
                <p style="color: #111827; font-size: 32px; font-weight: bold; margin: 0; letter-spacing: 4px; font-family: 'Courier New', monospace;">${activation_code}</p>
              </div>

              <p style="color: #6b7280; font-size: 14px; line-height: 1.6; margin: 0;">
                This gift will help you protect your home investment by keeping all your warranties, receipts, and maintenance records organized in one place.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: #f9fafb; padding: 30px 40px; border-top: 1px solid #e5e7eb;">
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td align="center" style="padding-bottom: 15px;">
                    <img src="https://havenkeep.com/logo.png" alt="HavenKeep" style="height: 32px;">
                  </td>
                </tr>
                <tr>
                  <td align="center">
                    <p style="color: #6b7280; font-size: 13px; line-height: 1.5; margin: 0 0 10px;">
                      HavenKeep — Your Warranties. Protected.
                    </p>
                    <p style="color: #9ca3af; font-size: 12px; margin: 0;">
                      This gift expires in 6 months. Questions? Contact us at support@havenkeep.com
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
      `;

      const textContent = `
You've Received a Gift from ${fromName}!

Hi ${firstName},

Congratulations on your new home! ${fromName} is excited to share a special gift with you: ${premium_months} months of HavenKeep Premium — completely free!

${custom_message ? `\n"${custom_message}"\n` : ''}

What's Included:
- ${premium_months} Months Premium — Full access to all features
- Unlimited Items — Track all your appliances & warranties
- Unlimited Documents — Store receipts, manuals & more
- Smart Reminders — Never miss a warranty expiration

Activate Your Gift:
${activation_url}

Or use activation code: ${activation_code}

This gift will help you protect your home investment by keeping all your warranties, receipts, and maintenance records organized in one place.

---
HavenKeep — Your Warranties. Protected.
This gift expires in 6 months. Questions? Contact us at support@havenkeep.com
      `;

      const msg = {
        to,
        from: {
          email: config.sendgrid.fromEmail,
          name: fromName,
        },
        replyTo: config.sendgrid.replyToEmail,
        subject: `🎁 ${fromName} sent you a gift: ${premium_months} Months HavenKeep Premium`,
        text: textContent,
        html: htmlContent,
      };

      await sgMail.send(msg);

      logger.info(
        {
          to,
          homebuyer_name,
          partner_name,
          activation_code,
        },
        'Gift activation email sent successfully'
      );
    } catch (error) {
      logger.error({ error, to: data.to }, 'Failed to send gift activation email');
      throw error;
    }
  }

  /**
   * Send welcome email to new partner
   */
  static async sendPartnerWelcomeEmail(data: {
    to: string;
    partner_name: string;
    company_name?: string;
  }): Promise<void> {
    try {
      const { to, partner_name, company_name } = data;
      const firstName = partner_name.split(' ')[0];

      const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to HavenKeep Partners</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">

          <tr>
            <td style="background: linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%); padding: 40px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold;">Welcome to HavenKeep Partners! 🎉</h1>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">Hi ${firstName},</p>

              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
                Thank you for joining the HavenKeep Partner Program! We're excited to help you provide exceptional value to your clients with our closing gift program.
              </p>

              <div style="background-color: #f9fafb; border-radius: 8px; padding: 30px; margin: 0 0 30px;">
                <h2 style="color: #111827; font-size: 20px; margin: 0 0 20px; font-weight: 600;">Next Steps</h2>

                <ol style="color: #374151; font-size: 15px; line-height: 1.8; margin: 0; padding-left: 20px;">
                  <li>Complete your profile and branding in the Partner Dashboard</li>
                  <li>Set your default gift message and premium months</li>
                  <li>Create your first closing gift</li>
                  <li>Share the gift link with your client</li>
                </ol>
              </div>

              <table width="100%" cellpadding="0" cellspacing="0" style="margin: 0 0 30px;">
                <tr>
                  <td align="center">
                    <a href="${config.app.dashboardUrl}" style="display: inline-block; background-color: #3B82F6; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
                      Go to Dashboard
                    </a>
                  </td>
                </tr>
              </table>

              <p style="color: #6b7280; font-size: 14px; line-height: 1.6; margin: 0;">
                Questions? Our team is here to help at <a href="mailto:partners@havenkeep.com" style="color: #3B82F6; text-decoration: none;">partners@havenkeep.com</a>
              </p>
            </td>
          </tr>

          <tr>
            <td style="background-color: #f9fafb; padding: 30px 40px; border-top: 1px solid #e5e7eb; text-align: center;">
              <p style="color: #6b7280; font-size: 13px; margin: 0;">
                HavenKeep Partners — Delight Your Clients
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
      `;

      const msg = {
        to,
        from: {
          email: config.sendgrid.fromEmail,
          name: 'HavenKeep Partners',
        },
        replyTo: 'partners@havenkeep.com',
        subject: 'Welcome to HavenKeep Partners! 🎉',
        html: htmlContent,
      };

      await sgMail.send(msg);

      logger.info({ to, partner_name }, 'Partner welcome email sent successfully');
    } catch (error) {
      logger.error({ error, to: data.to }, 'Failed to send partner welcome email');
      throw error;
    }
  }
}
