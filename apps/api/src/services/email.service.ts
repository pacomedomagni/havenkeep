import sgMail from '@sendgrid/mail';
import { logger } from '../utils/logger';
import { config } from '../config';

// Initialize SendGrid
if (config.sendgrid.apiKey) {
  sgMail.setApiKey(config.sendgrid.apiKey);
}

// Sanitize user input for safe HTML embedding
function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// Validate hex color format
function sanitizeColor(color: string): string {
  return /^#[0-9A-Fa-f]{6}$/.test(color) ? color : '#3B82F6';
}

// Validate URL is https (allow http only for localhost in development)
function sanitizeUrl(url: string): string {
  try {
    const parsed = new URL(url);
    if (parsed.protocol === 'https:') {
      return url;
    }
    // Allow http only for localhost in development
    if (parsed.protocol === 'http:' && (parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1')) {
      return url;
    }
    return '';
  } catch {
    return '';
  }
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
        brand_color: rawColor = '#3B82F6',
        logo_url: rawLogoUrl,
      } = data;

      // Sanitize all user-provided inputs
      const brand_color = sanitizeColor(rawColor);
      const logo_url = rawLogoUrl ? sanitizeUrl(rawLogoUrl) : '';

      const fromName = escapeHtml(partner_company || partner_name);
      const firstName = escapeHtml(homebuyer_name.split(' ')[0]);
      const safeActivationUrl = sanitizeUrl(activation_url);
      const safeCustomMessage = custom_message ? escapeHtml(custom_message) : '';

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

              ${safeCustomMessage ? `
              <div style="background-color: ${brand_color}10; border-left: 4px solid ${brand_color}; padding: 20px; margin: 0 0 30px; border-radius: 4px;">
                <p style="color: #374151; font-size: 15px; line-height: 1.6; margin: 0; font-style: italic;">
                  "${safeCustomMessage}"
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
                    <a href="${safeActivationUrl}" style="display: inline-block; background-color: ${brand_color}; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
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
                    <img src="${config.app.baseUrl}/logo.png" alt="HavenKeep" style="height: 32px;">
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
${safeActivationUrl}

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

  /**
   * Send warranty expiration reminder email
   */
  static async sendWarrantyExpirationEmail(data: {
    to: string;
    user_name: string;
    item_name: string;
    brand?: string;
    expiry_date: string;
    days_remaining: number;
    item_id: string;
  }): Promise<void> {
    try {
      const { to, user_name, item_name, brand, expiry_date, days_remaining, item_id } = data;

      const firstName = escapeHtml(user_name.split(' ')[0]);
      const safeItemName = escapeHtml(brand ? `${brand} ${item_name}` : item_name);
      const safeExpiryDate = escapeHtml(expiry_date);
      const itemUrl = `${config.app.frontendUrl}/items/${item_id}`;

      const urgencyColor = days_remaining <= 7 ? '#EF4444' : days_remaining <= 14 ? '#F59E0B' : '#3B82F6';
      const urgencyLabel = days_remaining <= 7 ? 'Expiring Very Soon' : days_remaining <= 14 ? 'Expiring Soon' : 'Expiring';

      const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Warranty ${urgencyLabel}</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">

          <tr>
            <td style="background: linear-gradient(135deg, ${urgencyColor} 0%, ${urgencyColor}dd 100%); padding: 40px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold;">Warranty ${urgencyLabel}</h1>
              <p style="color: #ffffff; margin: 10px 0 0; font-size: 16px; opacity: 0.95;">${days_remaining} day${days_remaining !== 1 ? 's' : ''} remaining</p>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">Hi ${firstName},</p>

              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 30px;">
                Your warranty for <strong>${safeItemName}</strong> expires on <strong>${safeExpiryDate}</strong>. Now is a good time to review your coverage and take action if needed.
              </p>

              <div style="background-color: #f9fafb; border-radius: 8px; padding: 30px; margin: 0 0 30px;">
                <h2 style="color: #111827; font-size: 20px; margin: 0 0 20px; font-weight: 600;">What You Can Do</h2>
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">Check if the manufacturer offers an extended warranty</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">File any pending warranty claims before expiration</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">Document the current condition of your item</span>
                    </td>
                  </tr>
                </table>
              </div>

              <table width="100%" cellpadding="0" cellspacing="0" style="margin: 0 0 30px;">
                <tr>
                  <td align="center">
                    <a href="${itemUrl}" style="display: inline-block; background-color: ${urgencyColor}; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
                      View Your Item
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <tr>
            <td style="background-color: #f9fafb; padding: 30px 40px; border-top: 1px solid #e5e7eb; text-align: center;">
              <p style="color: #6b7280; font-size: 13px; line-height: 1.5; margin: 0 0 10px;">
                HavenKeep — Your Warranties. Protected.
              </p>
              <p style="color: #9ca3af; font-size: 12px; margin: 0;">
                You're receiving this because you have email notifications enabled. Manage your preferences in the app.
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

      const textContent = `
Warranty ${urgencyLabel} — ${days_remaining} day${days_remaining !== 1 ? 's' : ''} remaining

Hi ${firstName},

Your warranty for ${safeItemName} expires on ${safeExpiryDate}. Now is a good time to review your coverage and take action if needed.

What You Can Do:
- Check if the manufacturer offers an extended warranty
- File any pending warranty claims before expiration
- Document the current condition of your item

View Your Item: ${itemUrl}

---
HavenKeep — Your Warranties. Protected.
You're receiving this because you have email notifications enabled.
      `;

      const msg = {
        to,
        from: {
          email: config.sendgrid.fromEmail,
          name: 'HavenKeep',
        },
        replyTo: config.sendgrid.replyToEmail,
        subject: `Warranty ${urgencyLabel}: ${safeItemName} expires ${safeExpiryDate}`,
        text: textContent,
        html: htmlContent,
      };

      await sgMail.send(msg);

      logger.info({ to, item_name, expiry_date, days_remaining }, 'Warranty expiration email sent');
    } catch (error) {
      logger.error({ error, to: data.to, item_id: data.item_id }, 'Failed to send warranty expiration email');
      throw error;
    }
  }

  /**
   * Send email verification email
   */
  static async sendEmailVerificationEmail(data: {
    to: string;
    user_name: string;
    verify_url: string;
  }): Promise<void> {
    try {
      const { to, user_name, verify_url } = data;

      const firstName = escapeHtml(user_name.split(' ')[0]);
      const safeVerifyUrl = sanitizeUrl(verify_url);

      if (!safeVerifyUrl) {
        throw new Error('Invalid verification URL');
      }

      const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Verify Your Email</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">

          <tr>
            <td style="background: linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%); padding: 40px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold;">Verify Your Email</h1>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">Hi ${firstName},</p>

              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 30px;">
                Welcome to HavenKeep! Please verify your email address by clicking the button below. This link expires in <strong>24 hours</strong>.
              </p>

              <table width="100%" cellpadding="0" cellspacing="0" style="margin: 0 0 30px;">
                <tr>
                  <td align="center">
                    <a href="${safeVerifyUrl}" style="display: inline-block; background-color: #3B82F6; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
                      Verify Email
                    </a>
                  </td>
                </tr>
              </table>

              <p style="color: #9ca3af; font-size: 13px; line-height: 1.6; margin: 0;">
                If the button doesn't work, copy and paste this link into your browser:<br>
                <span style="color: #3B82F6; word-break: break-all;">${safeVerifyUrl}</span>
              </p>
            </td>
          </tr>

          <tr>
            <td style="background-color: #f9fafb; padding: 30px 40px; border-top: 1px solid #e5e7eb; text-align: center;">
              <p style="color: #6b7280; font-size: 13px; margin: 0;">
                HavenKeep — Your Warranties. Protected.
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

      const textContent = `
Verify Your Email

Hi ${firstName},

Welcome to HavenKeep! Please verify your email address by clicking the link below. This link expires in 24 hours.

Verify Email: ${safeVerifyUrl}

---
HavenKeep — Your Warranties. Protected.
      `;

      const msg = {
        to,
        from: {
          email: config.sendgrid.fromEmail,
          name: 'HavenKeep',
        },
        replyTo: config.sendgrid.replyToEmail,
        subject: 'Verify your HavenKeep email address',
        text: textContent,
        html: htmlContent,
      };

      await sgMail.send(msg);

      logger.info({ to }, 'Verification email sent');
    } catch (error) {
      logger.error({ error, to: data.to }, 'Failed to send verification email');
      throw error;
    }
  }

  /**
   * Send password reset email
   */
  static async sendPasswordResetEmail(data: {
    to: string;
    user_name: string;
    reset_url: string;
  }): Promise<void> {
    try {
      const { to, user_name, reset_url } = data;

      const firstName = escapeHtml(user_name.split(' ')[0]);
      const safeResetUrl = sanitizeUrl(reset_url);

      if (!safeResetUrl) {
        throw new Error('Invalid reset URL');
      }

      const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Reset Your Password</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">

          <tr>
            <td style="background: linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%); padding: 40px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold;">Reset Your Password</h1>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">Hi ${firstName},</p>

              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 30px;">
                We received a request to reset your password. Click the button below to create a new password. This link expires in <strong>1 hour</strong>.
              </p>

              <table width="100%" cellpadding="0" cellspacing="0" style="margin: 0 0 30px;">
                <tr>
                  <td align="center">
                    <a href="${safeResetUrl}" style="display: inline-block; background-color: #3B82F6; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
                      Reset Password
                    </a>
                  </td>
                </tr>
              </table>

              <p style="color: #6b7280; font-size: 14px; line-height: 1.6; margin: 0 0 10px;">
                If you didn't request a password reset, you can safely ignore this email. Your password will remain unchanged.
              </p>

              <p style="color: #9ca3af; font-size: 13px; line-height: 1.6; margin: 0;">
                If the button doesn't work, copy and paste this link into your browser:<br>
                <span style="color: #3B82F6; word-break: break-all;">${safeResetUrl}</span>
              </p>
            </td>
          </tr>

          <tr>
            <td style="background-color: #f9fafb; padding: 30px 40px; border-top: 1px solid #e5e7eb; text-align: center;">
              <p style="color: #6b7280; font-size: 13px; margin: 0;">
                HavenKeep — Your Warranties. Protected.
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

      const textContent = `
Reset Your Password

Hi ${firstName},

We received a request to reset your password. Use the link below to create a new password. This link expires in 1 hour.

Reset Password: ${safeResetUrl}

If you didn't request a password reset, you can safely ignore this email.

---
HavenKeep — Your Warranties. Protected.
      `;

      const msg = {
        to,
        from: {
          email: config.sendgrid.fromEmail,
          name: 'HavenKeep',
        },
        replyTo: config.sendgrid.replyToEmail,
        subject: 'Reset your HavenKeep password',
        text: textContent,
        html: htmlContent,
      };

      await sgMail.send(msg);

      logger.info({ to }, 'Password reset email sent');
    } catch (error) {
      logger.error({ error, to: data.to }, 'Failed to send password reset email');
      throw error;
    }
  }
}
