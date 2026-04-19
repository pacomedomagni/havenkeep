"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.EmailService = void 0;
const mail_1 = __importDefault(require("@sendgrid/mail"));
const logger_1 = require("../utils/logger");
const config_1 = require("../config");
// Initialize SendGrid
if (config_1.config.sendgrid.apiKey) {
    mail_1.default.setApiKey(config_1.config.sendgrid.apiKey);
}
// Sanitize user input for safe HTML embedding
function escapeHtml(str) {
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}
// Validate hex color format
function sanitizeColor(color) {
    return /^#[0-9A-Fa-f]{6}$/.test(color) ? color : '#3B82F6';
}
// Validate URL is https (allow http only for localhost in development)
function sanitizeUrl(url) {
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
    }
    catch {
        return '';
    }
}
class EmailService {
    /**
     * Send partner gift activation email to homebuyer
     */
    static async sendGiftActivationEmail(data) {
        try {
            const { to, homebuyer_name, partner_name, partner_company, premium_months, activation_url, activation_code, custom_message, brand_color: rawColor = '#3B82F6', logo_url: rawLogoUrl, gift_id, } = data;
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
                    <img src="${config_1.config.app.baseUrl}/logo.png" alt="HavenKeep" style="height: 32px;">
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
  ${gift_id ? `<img src="${config_1.config.app.apiUrl}/api/v1/partners/gifts/${gift_id}/track/email-open" width="1" height="1" alt="" style="display:none">` : ''}
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
                    email: config_1.config.sendgrid.fromEmail,
                    name: fromName,
                },
                replyTo: config_1.config.sendgrid.replyToEmail,
                subject: `🎁 ${fromName} sent you a gift: ${premium_months} Months HavenKeep Premium`,
                text: textContent,
                html: htmlContent,
            };
            await mail_1.default.send(msg);
            logger_1.logger.info({
                to,
                homebuyer_name,
                partner_name,
                activation_code,
            }, 'Gift activation email sent successfully');
        }
        catch (error) {
            logger_1.logger.error({ error, to: data.to }, 'Failed to send gift activation email');
            throw error;
        }
    }
    /**
     * Send welcome email to new partner
     */
    static async sendPartnerWelcomeEmail(data) {
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
                    <a href="${config_1.config.app.dashboardUrl}" style="display: inline-block; background-color: #3B82F6; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
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
                    email: config_1.config.sendgrid.fromEmail,
                    name: 'HavenKeep Partners',
                },
                replyTo: 'partners@havenkeep.com',
                subject: 'Welcome to HavenKeep Partners! 🎉',
                html: htmlContent,
            };
            await mail_1.default.send(msg);
            logger_1.logger.info({ to, partner_name }, 'Partner welcome email sent successfully');
        }
        catch (error) {
            logger_1.logger.error({ error, to: data.to }, 'Failed to send partner welcome email');
            throw error;
        }
    }
    /**
     * Send warranty expiration reminder email
     */
    static async sendWarrantyExpirationEmail(data) {
        try {
            const { to, user_name, item_name, brand, expiry_date, days_remaining, item_id } = data;
            const firstName = escapeHtml(user_name.split(' ')[0]);
            const safeItemName = escapeHtml(brand ? `${brand} ${item_name}` : item_name);
            const safeExpiryDate = escapeHtml(expiry_date);
            const itemUrl = `${config_1.config.app.frontendUrl}/items/${item_id}`;
            const unsubscribeUrl = `${config_1.config.app.frontendUrl}/settings/notifications`;
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
              <p style="color: #9ca3af; font-size: 12px; margin: 10px 0 0;">
                To stop receiving these emails, <a href="${unsubscribeUrl}" style="color: #9ca3af; text-decoration: underline;">unsubscribe here</a>.
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
To stop receiving these emails, visit: ${unsubscribeUrl}
      `;
            const msg = {
                to,
                from: {
                    email: config_1.config.sendgrid.fromEmail,
                    name: 'HavenKeep',
                },
                replyTo: config_1.config.sendgrid.replyToEmail,
                subject: `Warranty ${urgencyLabel}: ${safeItemName} expires ${safeExpiryDate}`,
                text: textContent,
                html: htmlContent,
                headers: {
                    'List-Unsubscribe': `<${unsubscribeUrl}>`,
                    'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
                },
            };
            await mail_1.default.send(msg);
            logger_1.logger.info({ to, item_name, expiry_date, days_remaining }, 'Warranty expiration email sent');
        }
        catch (error) {
            logger_1.logger.error({ error, to: data.to, item_id: data.item_id }, 'Failed to send warranty expiration email');
            throw error;
        }
    }
    /**
     * Send maintenance due reminder email
     */
    static async sendMaintenanceDueEmail(data) {
        try {
            const { to, user_name, item_name, task_name, item_url } = data;
            const firstName = escapeHtml(user_name.split(' ')[0]);
            const safeItemName = escapeHtml(item_name);
            const safeTaskName = escapeHtml(task_name);
            const safeItemUrl = sanitizeUrl(item_url);
            const unsubscribeUrl = `${config_1.config.app.frontendUrl}/settings/notifications`;
            const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Maintenance Due</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">

          <tr>
            <td style="background: linear-gradient(135deg, #F59E0B 0%, #F59E0Bdd 100%); padding: 40px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold;">Maintenance Due</h1>
              <p style="color: #ffffff; margin: 10px 0 0; font-size: 16px; opacity: 0.95;">${safeTaskName}</p>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">Hi ${firstName},</p>

              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 30px;">
                It's time to perform maintenance on your <strong>${safeItemName}</strong>: <strong>${safeTaskName}</strong>. Keeping up with regular maintenance helps extend the life of your items and keeps warranties valid.
              </p>

              <div style="background-color: #f9fafb; border-radius: 8px; padding: 30px; margin: 0 0 30px;">
                <h2 style="color: #111827; font-size: 20px; margin: 0 0 20px; font-weight: 600;">What To Do</h2>
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">Complete the maintenance task as recommended</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">Log the completed task in HavenKeep to track your history</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">Check for any signs of wear or issues while performing maintenance</span>
                    </td>
                  </tr>
                </table>
              </div>

              <table width="100%" cellpadding="0" cellspacing="0" style="margin: 0 0 30px;">
                <tr>
                  <td align="center">
                    <a href="${safeItemUrl}" style="display: inline-block; background-color: #F59E0B; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
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
              <p style="color: #9ca3af; font-size: 12px; margin: 10px 0 0;">
                To stop receiving these emails, <a href="${unsubscribeUrl}" style="color: #9ca3af; text-decoration: underline;">unsubscribe here</a>.
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
Maintenance Due — ${safeTaskName}

Hi ${firstName},

It's time to perform maintenance on your ${safeItemName}: ${safeTaskName}. Keeping up with regular maintenance helps extend the life of your items and keeps warranties valid.

What To Do:
- Complete the maintenance task as recommended
- Log the completed task in HavenKeep to track your history
- Check for any signs of wear or issues while performing maintenance

View Your Item: ${safeItemUrl}

---
HavenKeep — Your Warranties. Protected.
You're receiving this because you have email notifications enabled.
To stop receiving these emails, visit: ${unsubscribeUrl}
      `;
            const msg = {
                to,
                from: {
                    email: config_1.config.sendgrid.fromEmail,
                    name: 'HavenKeep',
                },
                replyTo: config_1.config.sendgrid.replyToEmail,
                subject: `Maintenance Due: ${safeTaskName} for ${safeItemName}`,
                text: textContent,
                html: htmlContent,
                headers: {
                    'List-Unsubscribe': `<${unsubscribeUrl}>`,
                    'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
                },
            };
            await mail_1.default.send(msg);
            logger_1.logger.info({ to, item_name, task_name }, 'Maintenance due email sent');
        }
        catch (error) {
            logger_1.logger.error({ error, to: data.to, item_name: data.item_name }, 'Failed to send maintenance due email');
            throw error;
        }
    }
    /**
     * Send email verification email
     */
    static async sendEmailVerificationEmail(data) {
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
                    email: config_1.config.sendgrid.fromEmail,
                    name: 'HavenKeep',
                },
                replyTo: config_1.config.sendgrid.replyToEmail,
                subject: 'Verify your HavenKeep email address',
                text: textContent,
                html: htmlContent,
            };
            await mail_1.default.send(msg);
            logger_1.logger.info({ to }, 'Verification email sent');
        }
        catch (error) {
            logger_1.logger.error({ error, to: data.to }, 'Failed to send verification email');
            throw error;
        }
    }
    /**
     * Send email change verification email to the new address
     */
    static async sendEmailChangeVerificationEmail(data) {
        try {
            const { to, user_name, verify_url, new_email } = data;
            const firstName = escapeHtml(user_name.split(' ')[0]);
            const safeVerifyUrl = sanitizeUrl(verify_url);
            const safeNewEmail = escapeHtml(new_email);
            if (!safeVerifyUrl) {
                throw new Error('Invalid verification URL');
            }
            const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Confirm Your New Email</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">

          <tr>
            <td style="background: linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%); padding: 40px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold;">Confirm Your New Email</h1>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">Hi ${firstName},</p>

              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
                We received a request to change your HavenKeep account email to <strong>${safeNewEmail}</strong>. Please confirm this change by clicking the button below. This link expires in <strong>24 hours</strong>.
              </p>

              <p style="color: #6b7280; font-size: 14px; line-height: 1.6; margin: 0 0 30px;">
                If you did not request this change, you can safely ignore this email. Your email address will remain unchanged.
              </p>

              <table width="100%" cellpadding="0" cellspacing="0" style="margin: 0 0 30px;">
                <tr>
                  <td align="center">
                    <a href="${safeVerifyUrl}" style="display: inline-block; background-color: #3B82F6; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
                      Confirm New Email
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
Confirm Your New Email

Hi ${firstName},

We received a request to change your HavenKeep account email to ${safeNewEmail}. Please confirm this change by clicking the link below. This link expires in 24 hours.

If you did not request this change, you can safely ignore this email.

Confirm New Email: ${safeVerifyUrl}

---
HavenKeep — Your Warranties. Protected.
      `;
            const msg = {
                to,
                from: {
                    email: config_1.config.sendgrid.fromEmail,
                    name: 'HavenKeep',
                },
                replyTo: config_1.config.sendgrid.replyToEmail,
                subject: 'Confirm your new HavenKeep email address',
                text: textContent,
                html: htmlContent,
            };
            await mail_1.default.send(msg);
            logger_1.logger.info({ to, new_email }, 'Email change verification email sent');
        }
        catch (error) {
            logger_1.logger.error({ error, to: data.to }, 'Failed to send email change verification email');
            throw error;
        }
    }
    /**
     * Send account deletion confirmation email
     */
    static async sendAccountDeletionEmail(data) {
        try {
            const { to, user_name } = data;
            const firstName = escapeHtml(user_name.split(' ')[0]);
            const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Account Deleted</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">

          <tr>
            <td style="background: linear-gradient(135deg, #6B7280 0%, #4B5563 100%); padding: 40px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold;">Account Deleted</h1>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">Hi ${firstName},</p>

              <p style="color: #374151; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
                Your HavenKeep account has been successfully deleted. We're sorry to see you go.
              </p>

              <div style="background-color: #f9fafb; border-radius: 8px; padding: 30px; margin: 0 0 30px;">
                <h2 style="color: #111827; font-size: 20px; margin: 0 0 20px; font-weight: 600;">What Was Deleted</h2>
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">Your profile and account information</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">All homes, items, and warranty records</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">Maintenance logs and uploaded documents</span>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 8px 0;">
                      <span style="color: #374151; font-size: 15px;">Notification preferences and push tokens</span>
                    </td>
                  </tr>
                </table>
              </div>

              <div style="background-color: #FEF3C7; border-left: 4px solid #F59E0B; padding: 20px; margin: 0 0 30px; border-radius: 4px;">
                <p style="color: #374151; font-size: 15px; line-height: 1.6; margin: 0;">
                  <strong>Data Retention:</strong> In accordance with our privacy policy, anonymized analytics data may be retained for up to 30 days. After that period, all traces of your account will be permanently removed from our systems.
                </p>
              </div>

              <p style="color: #6b7280; font-size: 14px; line-height: 1.6; margin: 0;">
                If you didn't request this deletion or believe this was done in error, please contact us immediately at <a href="mailto:support@havenkeep.com" style="color: #3B82F6; text-decoration: none;">support@havenkeep.com</a>.
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
Account Deleted

Hi ${firstName},

Your HavenKeep account has been successfully deleted. We're sorry to see you go.

What Was Deleted:
- Your profile and account information
- All homes, items, and warranty records
- Maintenance logs and uploaded documents
- Notification preferences and push tokens

Data Retention: In accordance with our privacy policy, anonymized analytics data may be retained for up to 30 days. After that period, all traces of your account will be permanently removed from our systems.

If you didn't request this deletion or believe this was done in error, please contact us immediately at support@havenkeep.com.

---
HavenKeep — Your Warranties. Protected.
      `;
            const msg = {
                to,
                from: {
                    email: config_1.config.sendgrid.fromEmail,
                    name: 'HavenKeep',
                },
                replyTo: config_1.config.sendgrid.replyToEmail,
                subject: 'Your HavenKeep account has been deleted',
                text: textContent,
                html: htmlContent,
            };
            await mail_1.default.send(msg);
            logger_1.logger.info({ to }, 'Account deletion confirmation email sent');
        }
        catch (error) {
            logger_1.logger.error({ error, to: data.to }, 'Failed to send account deletion email');
            throw error;
        }
    }
    /**
     * Send password reset email
     */
    static async sendPasswordResetEmail(data) {
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
                    email: config_1.config.sendgrid.fromEmail,
                    name: 'HavenKeep',
                },
                replyTo: config_1.config.sendgrid.replyToEmail,
                subject: 'Reset your HavenKeep password',
                text: textContent,
                html: htmlContent,
            };
            await mail_1.default.send(msg);
            logger_1.logger.info({ to }, 'Password reset email sent');
        }
        catch (error) {
            logger_1.logger.error({ error, to: data.to }, 'Failed to send password reset email');
            throw error;
        }
    }
    /**
     * Send contact form notification email to the support team
     */
    static async sendContactNotificationEmail(data) {
        try {
            const { name, email, subject, message } = data;
            const safeName = escapeHtml(name);
            const safeEmail = escapeHtml(email);
            const safeSubject = escapeHtml(subject);
            const safeMessage = escapeHtml(message);
            const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>New Contact Form Submission</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">

          <tr>
            <td style="background: linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%); padding: 40px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">New Contact Form Submission</h1>
            </td>
          </tr>

          <tr>
            <td style="padding: 40px;">
              <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 24px;">
                <tr>
                  <td style="padding: 12px 0; border-bottom: 1px solid #e5e7eb;">
                    <strong style="color: #6b7280; font-size: 14px;">From:</strong>
                    <div style="color: #111827; font-size: 16px; margin-top: 4px;">${safeName} &lt;${safeEmail}&gt;</div>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 12px 0; border-bottom: 1px solid #e5e7eb;">
                    <strong style="color: #6b7280; font-size: 14px;">Subject:</strong>
                    <div style="color: #111827; font-size: 16px; margin-top: 4px;">${safeSubject}</div>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 12px 0;">
                    <strong style="color: #6b7280; font-size: 14px;">Message:</strong>
                    <div style="color: #374151; font-size: 16px; line-height: 1.6; margin-top: 8px; white-space: pre-wrap;">${safeMessage}</div>
                  </td>
                </tr>
              </table>

              <p style="color: #9ca3af; font-size: 13px; margin: 0;">
                Reply directly to this email to respond to the sender.
              </p>
            </td>
          </tr>

          <tr>
            <td style="background-color: #f9fafb; padding: 20px 40px; text-align: center; border-top: 1px solid #e5e7eb;">
              <p style="color: #9ca3af; font-size: 12px; margin: 0;">HavenKeep Contact Form</p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
            const textContent = `New Contact Form Submission\n\nFrom: ${name} <${email}>\nSubject: ${subject}\n\nMessage:\n${message}`;
            const msg = {
                to: 'support@havenkeep.com',
                from: {
                    email: config_1.config.sendgrid.fromEmail,
                    name: 'HavenKeep Contact Form',
                },
                replyTo: email,
                subject: `Contact Form: ${subject} - ${name}`,
                text: textContent,
                html: htmlContent,
            };
            await mail_1.default.send(msg);
            logger_1.logger.info({ from: email, subject }, 'Contact notification email sent');
        }
        catch (error) {
            logger_1.logger.error({ error, from: data.email }, 'Failed to send contact notification email');
            throw error;
        }
    }
}
exports.EmailService = EmailService;
//# sourceMappingURL=email.service.js.map