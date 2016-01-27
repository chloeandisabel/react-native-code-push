package com.microsoft.codepush.react;

import android.content.Context;
import android.content.SharedPreferences;

import com.facebook.react.bridge.WritableMap;

public class CodePushStatusReport {

    private Context applicationContext;
    private final String CODE_PUSH_PREFERENCES;
    private final String DEPLOYMENT_KEY_KEY = "deploymentKey";
    private final String LABEL_KEY = "label";
    private final String LAST_DEPLOYMENT_REPORT_KEY = "CODE_PUSH_LAST_DEPLOYMENT_REPORT";

    public CodePushStatusReport(Context applicationContext, String codePushPreferencesKey) {
        this.applicationContext = applicationContext;
        this.CODE_PUSH_PREFERENCES = codePushPreferencesKey;
    }

    public String getDeploymentKeyFromStatusReportIdentifier(String statusReportIdentifier) {
        String[] parsedIdentifier = statusReportIdentifier.split(":");
        if (parsedIdentifier.length > 0) {
            return parsedIdentifier[0];
        } else {
            return null;
        }
    }

    public String getPackageStatusReportIdentifier(WritableMap updatePackage) {
        // Because deploymentKeys can be dynamically switched, we use a
        // combination of the deploymentKey and label as the packageIdentifier.
        String deploymentKey = CodePushUtils.tryGetString(updatePackage, DEPLOYMENT_KEY_KEY);
        String label = CodePushUtils.tryGetString(updatePackage, LABEL_KEY);
        if (deploymentKey != null && label != null) {
            return deploymentKey + ":" + label;
        } else {
            return null;
        }
    }

    public String getPreviousStatusReportIdentifier() {
        SharedPreferences settings = applicationContext.getSharedPreferences(CODE_PUSH_PREFERENCES, 0);
        return settings.getString(LAST_DEPLOYMENT_REPORT_KEY, null);
    }

    public String getVersionLabelFromStatusReportIdentifier(String statusReportIdentifier) {
        String[] parsedIdentifier = statusReportIdentifier.split(":");
        if (parsedIdentifier.length > 1) {
            return parsedIdentifier[1];
        } else {
            return null;
        }
    }

    public boolean isStatusReportIdentifierCodePushLabel(String statusReportIdentifier) {
        return statusReportIdentifier != null && statusReportIdentifier.contains(":");
    }

    public void recordDeploymentStatusReported(String appVersionOrPackageIdentifier) {
        SharedPreferences settings = applicationContext.getSharedPreferences(CODE_PUSH_PREFERENCES, 0);
        settings.edit().putString(LAST_DEPLOYMENT_REPORT_KEY, appVersionOrPackageIdentifier).commit();
    }
}