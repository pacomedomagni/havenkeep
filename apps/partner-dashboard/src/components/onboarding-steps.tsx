'use client';

interface OnboardingStepsProps {
  currentStep: number;
  totalSteps: number;
}

export default function OnboardingSteps({ currentStep, totalSteps }: OnboardingStepsProps) {
  return (
    <div className="flex items-center justify-center gap-3 mb-8">
      {Array.from({ length: totalSteps }, (_, i) => {
        const step = i + 1;
        const isActive = step === currentStep;
        const isCompleted = step < currentStep;

        return (
          <div key={step} className="flex items-center gap-3">
            <div
              className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium transition-colors duration-200 ${
                isActive
                  ? 'bg-haven-primary text-white'
                  : isCompleted
                  ? 'bg-haven-active text-white'
                  : 'bg-haven-elevated text-haven-text-tertiary border border-haven-border'
              }`}
            >
              {isCompleted ? (
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              ) : (
                step
              )}
            </div>
            {step < totalSteps && (
              <div
                className={`w-12 h-0.5 ${
                  isCompleted ? 'bg-haven-active' : 'bg-haven-border'
                }`}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}
