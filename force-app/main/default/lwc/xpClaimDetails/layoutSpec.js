// Gerado por salesforce/claim-tabs/build-details.cjs a partir do spec.cjs. Não editar à mão.
export const TABS = [
    {
        "id": "client",
        "title": "Client",
        "cond": null,
        "forms": false,
        "sections": [
            {
                "key": "client-0",
                "name": "Claim",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Name",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Claim_Type_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "CurrencyIsoCode",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Blocker__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Validation_Notes__c",
                            "behavior": "Readonly"
                        }
                    ],
                    [
                        {
                            "api": "Status__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Track__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Notes__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "client-1",
                "name": "Client links",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Full_Form_Link__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Step__c",
                            "behavior": "Readonly"
                        }
                    ],
                    [
                        {
                            "api": "Short_Form_Link__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Agent_Form_Step__c",
                            "behavior": "Readonly"
                        }
                    ]
                ]
            },
            {
                "key": "client-2",
                "name": "Identity",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Claimant_title__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "First_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Last_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_dob__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Has_Nino__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_other_names__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Did_Client_Change_Name__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Claimant_Middle_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_maiden_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Age__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Claimant_nino__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "PPS__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "client-3",
                "name": "Contact",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Email__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_address1__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_City__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Eircode__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Eircode_Verified__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Contact__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Phone__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_address2__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Current_Address_Abroad_State_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Current_Address_Abroad_Country_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Address_Validated__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "client-4",
                "name": "Helper",
                "cond": "helper",
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Wants_Helper__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Friend_First_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Relationship__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Friend_Email__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Friend_Last_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "CC_Helper_on_All_Comms__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Friend_Phone__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "client-5",
                "name": "Family",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Claimant_marital_Status__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_date_Of_Marriage__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_date_Of_Bereavement__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Date_Of_Remarriage__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Marriage_Notes__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Claimant_Minded_Kids__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_date_Of_Divorce__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Previous_Marriage_Ended__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            }
        ]
    },
    {
        "id": "partner",
        "title": "Partner",
        "cond": "partner",
        "forms": false,
        "sections": [
            {
                "key": "partner-0",
                "name": "Partner",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Partner_Title__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_First_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Surname__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_DOB__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Claiming_UK_Pension__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Reference_on_Any_DWP_Letters__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Is_Partner_alive__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Other_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Maiden_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Has_Nino_values__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Nino__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "partner-1",
                "name": "In the UK",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Partner_Ever_Lived_UK__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Left_UK__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Ever_Lived_UK_Notes__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Partner_Ever_Worked_UK__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Towns_Lived__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "partner-2",
                "name": "Benefits ever claimed",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Partner_State_Pension__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Widows_Benefit__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_is_Waiting_Uk_Benefits__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Partner_Graduated_Retirement_Benefit__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Bereavement_Benefit__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_is_Waiting_Uk_Benefits_text__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "partner-3",
                "name": "Address",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Partner_same_as_claimant__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Address1__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_City__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Postcode__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Partner_Address_Unknown__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Address2__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_State_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Country__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "partner-4",
                "name": "Current husband / wife (remarried)",
                "cond": "remarried",
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Current_Spouse_First_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Current_Spouse_DOB__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Current_Spouse_Last_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Current_Spouse_Nino__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            }
        ]
    },
    {
        "id": "history",
        "title": "UK & Abroad",
        "cond": null,
        "forms": false,
        "sections": [
            {
                "key": "history-0",
                "name": "In the UK",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Claimant_ever_Lived_UK__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_lived_UK_From__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_Ever_Lived_UK_Notes__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_Ever_Worked_UK__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_worked_UK_From__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_has_Proof_Of_UK_Work__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Approx_Years_in_UK__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_lived_UK_to__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Ever_Live_In_UK_approved__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Ever_Worked_UK_Use_Same_Dates__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_worked_UK_To__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Ever_Work_UK_approved__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "history-1",
                "name": "HM Forces",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Claimant_HM_Forces__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_HM_Forces_Enlisted__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_HM_Forces_Discharged_Where__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_HM_Forces_Service_No__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Claimant_HM_Forces_Service__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_HM_Forces_Discharged__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_HM_Forces_Regiment__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_HM_Forces_Rank__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "history-2",
                "name": "NI contributions",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Ever_Self_Employed_UK_after_1978__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Work_In_UK_during_2_years__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Ever_Pay_Reduced_UK_nino__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "history-3",
                "name": "Abroad",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Claimant_nationality__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Is_Your_Partner_Currently_Get_Pension__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "isYourPartnerCurrentlyGetPensionText__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            }
        ]
    },
    {
        "id": "dwp",
        "title": "DWP",
        "cond": null,
        "forms": false,
        "sections": [
            {
                "key": "dwp-0",
                "name": "Sent to DWP",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "DocuSign_Date__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Big_Envelop_Posted_Date__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Process_Claim_Email_Date__c",
                            "behavior": "Readonly"
                        }
                    ],
                    [
                        {
                            "api": "Tracking_Number__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Big_Envelop_Tracking_Number__c",
                            "behavior": "Readonly"
                        }
                    ]
                ]
            },
            {
                "key": "dwp-1",
                "name": "DWP answer",
                "cond": "award",
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Award_Amount_GBP__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "DWP_Payment_Date__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Award_Amount__c",
                            "behavior": "Readonly"
                        }
                    ]
                ]
            }
        ]
    },
    {
        "id": "pension",
        "title": "Pension",
        "cond": null,
        "forms": false,
        "sections": [
            {
                "key": "pension-0",
                "name": "State Pension",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Pension_Claiming_from_Today__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Pension_Deferred_Pension__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Pension_Work_After_Pension_Age__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Pension_Start_Date__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Paid_Interval__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Pension_Imprisoned_Since_Pension_Age__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "pension-1",
                "name": "Benefits ever claimed",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Claimant_State_Pension__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_Widows_Benefit__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_is_Waiting_Uk_Benefits__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Claimant_Graduated_Retirement_Benefit__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_Bereavement_Benefit__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_is_Waiting_Uk_Benefits_text__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "pension-2",
                "name": "Australia",
                "cond": "au",
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Age_Pension_now_or_next_year__c",
                            "behavior": "Edit"
                        }
                    ],
                    []
                ]
            },
            {
                "key": "pension-3",
                "name": "Tax & UK property",
                "cond": null,
                "list": "ukProperties",
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Are_you_self_assessed_for_tax__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Do_you_own_rent_any_UK_property__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Do_you_have_an_accountant__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "pension-4",
                "name": "Accountant",
                "cond": "accountant",
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Accountant_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Accountant_Address__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Accountant_City__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Accountant_PostCode__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Accountant_Phone__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Accountant_Address_2__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Accountant_State_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Accountant_Country_Name__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            }
        ]
    },
    {
        "id": "bank",
        "title": "Bank",
        "cond": null,
        "forms": false,
        "sections": [
            {
                "key": "bank-0",
                "name": "Account holder",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Owns_This_Account__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_Account_Owner_Email__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Bank_Account_Owner_Name__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "bank-1",
                "name": "Account",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Bank_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_IBAN__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_Account__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Bank_Account_Type__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_BIC__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_Sort_Code__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "bank-2",
                "name": "Bank address",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Bank_Address__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_Post_Code__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Bank_City__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_Country__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_Country_Code__c",
                            "behavior": "Readonly"
                        }
                    ]
                ]
            }
        ]
    },
    {
        "id": "payment",
        "title": "Sale & Payment",
        "cond": null,
        "forms": false,
        "sections": [
            {
                "key": "payment-0",
                "name": "Sale",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Agent_Making_Sale__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "How_did_you_hear_about_us__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Sales_Call_A_Date__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Val_Call_Booked_Date__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Validation_Agent__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Val_Form_Complete__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Sales_Call_B_Date__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "payment-1",
                "name": "Payment",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Deposit_Paid__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Paid_Date__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Stripe_Customer_Id__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "LatestCharge__c",
                            "behavior": "Readonly"
                        }
                    ],
                    [
                        {
                            "api": "Deposit_Payment_Date__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Payment_Method__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Stripe_Transaction_Id__c",
                            "behavior": "Readonly"
                        }
                    ]
                ]
            },
            {
                "key": "payment-2",
                "name": "Direct Debit",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "GoCardless_Mandate_Id__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "GoCardless_Bank_Account_Id__c",
                            "behavior": "Readonly"
                        }
                    ],
                    [
                        {
                            "api": "GoCardless_Customer_Id__c",
                            "behavior": "Readonly"
                        }
                    ]
                ]
            }
        ]
    },
    {
        "id": "forms",
        "title": "IPCBR1 & IPC1394",
        "cond": null,
        "forms": true,
        "sections": []
    },
    {
        "id": "system",
        "title": "System",
        "cond": null,
        "forms": false,
        "sections": [
            {
                "key": "system-0",
                "name": "Record",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "CreatedById",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "CreatedDate",
                            "behavior": "Edit"
                        },
                        {
                            "api": "OwnerId",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "LastModifiedById",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "LastModifiedDate",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "system-1",
                "name": "Printing house upload",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "Is_envelope_created__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "FTP_Claim_Created_Send_Date__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "FTP_Claim_Created_ZIP_Error__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Claim_Full_Form_ZIP_for_UPLOAD__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "FTP_Claim_Full_Form_Error__c",
                            "behavior": "Readonly"
                        }
                    ],
                    [
                        {
                            "api": "Claim_Created_ZIP_for_UPLOAD__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "FTP_Claim_Created_Error__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Is_Test_Claim__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "FTP_Claim_Full_Form_Created_Send_Date__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "FTP_Claim_Full_Form_ZIP_Error__c",
                            "behavior": "Readonly"
                        }
                    ]
                ]
            },
            {
                "key": "system-2",
                "name": "E-sign follow-up calls",
                "cond": null,
                "list": null,
                "collapsed": false,
                "cols": [
                    [
                        {
                            "api": "X1st_Follow_Up_Call__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "X2nd_Follow_Up_Call__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "X3rd_Follow_Up_Call__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Call_Follow_Up_Change_User__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "X1st_Esign_Follow_Up_Call_Changed_Date__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "X2nd_Esign_Follow_Up_Call_Changed_Date__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "X3rd_Esign_Follow_Up_Call_Changed_Date__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "system-3",
                "name": "Address checks",
                "cond": null,
                "list": null,
                "collapsed": true,
                "cols": [
                    [
                        {
                            "api": "Verification_Status__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Verified_Reference__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Data8_Last_validation_date__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Verification_Status__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Verified_Reference__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Address_Validated__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Verification_Details__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Was_Cleansed__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Data8_Validation_result__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Verification_Details__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Was_Cleansed__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            },
            {
                "key": "system-4",
                "name": "Rarely used",
                "cond": null,
                "list": null,
                "collapsed": true,
                "cols": [
                    [
                        {
                            "api": "Claim_Type__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Validation_Agent_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Stage_1_Pack_Posted_Date__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Form_Agent_URL__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Agent_Form_Complete__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "IPC1394_Required__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "What_is_this_number__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_self_Employed_UK__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_hasNino__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "BSB_Number__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Has_Irish_Current_Account__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Confirmed_Date__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Has_Utility_Bill__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Contact_Type__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Last_Contact_Date__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Date_Since_Contact__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Days_Since_Contact__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Helper_Name__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "PPS_NINO__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Full_Current_Ad__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Current_Address_Abroad_Country__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Country_Code__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Accountant_Country_Code__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_Account_Number_formula__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "BR1_Snapshot_JSON__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Email_Text__c",
                            "behavior": "Edit"
                        }
                    ],
                    [
                        {
                            "api": "Missing_Info__c",
                            "behavior": "Readonly"
                        },
                        {
                            "api": "Stage_1_Pack_Tracking_Number__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Short_Agent_Link__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Validation_Form_Complete__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "IPC1349_Required__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Preferred_Channel__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Claimant_Ever_Paid_Married_Woman_s_Stam__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Has_Nino__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Age_Pension_AUS__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Opening_Status__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Has_Photo_ID__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Close_CRM_Lead_Id__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Who__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Last_Contact_At__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Days_Since_Last_Contact__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Days_Since_Contact_Data__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Customer__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_Full_Name__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Current_Address_Abroad__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Current_Address_Abroad_State__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Partner_State_Code__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Accountant_State_Code__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Bank_Sort_Code_formula__c",
                            "behavior": "Edit"
                        },
                        {
                            "api": "Personal_Details_Form_Link__c",
                            "behavior": "Edit"
                        }
                    ]
                ]
            }
        ]
    }
];

export const LOCATION = {
    "Name": {
        "tab": "client",
        "section": "client-0",
        "label": "Client › Claim"
    },
    "Claim_Type_Name__c": {
        "tab": "client",
        "section": "client-0",
        "label": "Client › Claim"
    },
    "CurrencyIsoCode": {
        "tab": "client",
        "section": "client-0",
        "label": "Client › Claim"
    },
    "Blocker__c": {
        "tab": "client",
        "section": "client-0",
        "label": "Client › Claim"
    },
    "Validation_Notes__c": {
        "tab": "client",
        "section": "client-0",
        "label": "Client › Claim"
    },
    "Status__c": {
        "tab": "client",
        "section": "client-0",
        "label": "Client › Claim"
    },
    "Track__c": {
        "tab": "client",
        "section": "client-0",
        "label": "Client › Claim"
    },
    "Notes__c": {
        "tab": "client",
        "section": "client-0",
        "label": "Client › Claim"
    },
    "Full_Form_Link__c": {
        "tab": "client",
        "section": "client-1",
        "label": "Client › Client links"
    },
    "Step__c": {
        "tab": "client",
        "section": "client-1",
        "label": "Client › Client links"
    },
    "Short_Form_Link__c": {
        "tab": "client",
        "section": "client-1",
        "label": "Client › Client links"
    },
    "Agent_Form_Step__c": {
        "tab": "client",
        "section": "client-1",
        "label": "Client › Client links"
    },
    "Claimant_title__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "First_Name__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Last_Name__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Claimant_dob__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Has_Nino__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Claimant_other_names__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Did_Client_Change_Name__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Claimant_Middle_Name__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Claimant_maiden_Name__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Age__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Claimant_nino__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "PPS__c": {
        "tab": "client",
        "section": "client-2",
        "label": "Client › Identity"
    },
    "Email__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Claimant_address1__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Claimant_City__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Eircode__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Eircode_Verified__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Contact__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Phone__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Claimant_address2__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Current_Address_Abroad_State_Name__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Current_Address_Abroad_Country_Name__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Address_Validated__c": {
        "tab": "client",
        "section": "client-3",
        "label": "Client › Contact"
    },
    "Wants_Helper__c": {
        "tab": "client",
        "section": "client-4",
        "label": "Client › Helper"
    },
    "Friend_First_Name__c": {
        "tab": "client",
        "section": "client-4",
        "label": "Client › Helper"
    },
    "Relationship__c": {
        "tab": "client",
        "section": "client-4",
        "label": "Client › Helper"
    },
    "Friend_Email__c": {
        "tab": "client",
        "section": "client-4",
        "label": "Client › Helper"
    },
    "Friend_Last_Name__c": {
        "tab": "client",
        "section": "client-4",
        "label": "Client › Helper"
    },
    "CC_Helper_on_All_Comms__c": {
        "tab": "client",
        "section": "client-4",
        "label": "Client › Helper"
    },
    "Friend_Phone__c": {
        "tab": "client",
        "section": "client-4",
        "label": "Client › Helper"
    },
    "Claimant_marital_Status__c": {
        "tab": "client",
        "section": "client-5",
        "label": "Client › Family"
    },
    "Claimant_date_Of_Marriage__c": {
        "tab": "client",
        "section": "client-5",
        "label": "Client › Family"
    },
    "Claimant_date_Of_Bereavement__c": {
        "tab": "client",
        "section": "client-5",
        "label": "Client › Family"
    },
    "Date_Of_Remarriage__c": {
        "tab": "client",
        "section": "client-5",
        "label": "Client › Family"
    },
    "Marriage_Notes__c": {
        "tab": "client",
        "section": "client-5",
        "label": "Client › Family"
    },
    "Claimant_Minded_Kids__c": {
        "tab": "client",
        "section": "client-5",
        "label": "Client › Family"
    },
    "Claimant_date_Of_Divorce__c": {
        "tab": "client",
        "section": "client-5",
        "label": "Client › Family"
    },
    "Previous_Marriage_Ended__c": {
        "tab": "client",
        "section": "client-5",
        "label": "Client › Family"
    },
    "Partner_Title__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_First_Name__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_Surname__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_DOB__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_Claiming_UK_Pension__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_Reference_on_Any_DWP_Letters__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Is_Partner_alive__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_Other_Name__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_Maiden_Name__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_Has_Nino_values__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_Nino__c": {
        "tab": "partner",
        "section": "partner-0",
        "label": "Partner › Partner"
    },
    "Partner_Ever_Lived_UK__c": {
        "tab": "partner",
        "section": "partner-1",
        "label": "Partner › In the UK"
    },
    "Partner_Left_UK__c": {
        "tab": "partner",
        "section": "partner-1",
        "label": "Partner › In the UK"
    },
    "Partner_Ever_Lived_UK_Notes__c": {
        "tab": "partner",
        "section": "partner-1",
        "label": "Partner › In the UK"
    },
    "Partner_Ever_Worked_UK__c": {
        "tab": "partner",
        "section": "partner-1",
        "label": "Partner › In the UK"
    },
    "Partner_Towns_Lived__c": {
        "tab": "partner",
        "section": "partner-1",
        "label": "Partner › In the UK"
    },
    "Partner_State_Pension__c": {
        "tab": "partner",
        "section": "partner-2",
        "label": "Partner › Benefits ever claimed"
    },
    "Partner_Widows_Benefit__c": {
        "tab": "partner",
        "section": "partner-2",
        "label": "Partner › Benefits ever claimed"
    },
    "Partner_is_Waiting_Uk_Benefits__c": {
        "tab": "partner",
        "section": "partner-2",
        "label": "Partner › Benefits ever claimed"
    },
    "Partner_Graduated_Retirement_Benefit__c": {
        "tab": "partner",
        "section": "partner-2",
        "label": "Partner › Benefits ever claimed"
    },
    "Partner_Bereavement_Benefit__c": {
        "tab": "partner",
        "section": "partner-2",
        "label": "Partner › Benefits ever claimed"
    },
    "Partner_is_Waiting_Uk_Benefits_text__c": {
        "tab": "partner",
        "section": "partner-2",
        "label": "Partner › Benefits ever claimed"
    },
    "Partner_same_as_claimant__c": {
        "tab": "partner",
        "section": "partner-3",
        "label": "Partner › Address"
    },
    "Partner_Address1__c": {
        "tab": "partner",
        "section": "partner-3",
        "label": "Partner › Address"
    },
    "Partner_City__c": {
        "tab": "partner",
        "section": "partner-3",
        "label": "Partner › Address"
    },
    "Partner_Postcode__c": {
        "tab": "partner",
        "section": "partner-3",
        "label": "Partner › Address"
    },
    "Partner_Address_Unknown__c": {
        "tab": "partner",
        "section": "partner-3",
        "label": "Partner › Address"
    },
    "Partner_Address2__c": {
        "tab": "partner",
        "section": "partner-3",
        "label": "Partner › Address"
    },
    "Partner_State_Name__c": {
        "tab": "partner",
        "section": "partner-3",
        "label": "Partner › Address"
    },
    "Partner_Country__c": {
        "tab": "partner",
        "section": "partner-3",
        "label": "Partner › Address"
    },
    "Current_Spouse_First_Name__c": {
        "tab": "partner",
        "section": "partner-4",
        "label": "Partner › Current husband / wife (remarried)"
    },
    "Current_Spouse_DOB__c": {
        "tab": "partner",
        "section": "partner-4",
        "label": "Partner › Current husband / wife (remarried)"
    },
    "Current_Spouse_Last_Name__c": {
        "tab": "partner",
        "section": "partner-4",
        "label": "Partner › Current husband / wife (remarried)"
    },
    "Current_Spouse_Nino__c": {
        "tab": "partner",
        "section": "partner-4",
        "label": "Partner › Current husband / wife (remarried)"
    },
    "Claimant_ever_Lived_UK__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Claimant_lived_UK_From__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Claimant_Ever_Lived_UK_Notes__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Claimant_Ever_Worked_UK__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Claimant_worked_UK_From__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Claimant_has_Proof_Of_UK_Work__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Approx_Years_in_UK__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Claimant_lived_UK_to__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Ever_Live_In_UK_approved__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Ever_Worked_UK_Use_Same_Dates__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Claimant_worked_UK_To__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Ever_Work_UK_approved__c": {
        "tab": "history",
        "section": "history-0",
        "label": "UK & Abroad › In the UK"
    },
    "Claimant_HM_Forces__c": {
        "tab": "history",
        "section": "history-1",
        "label": "UK & Abroad › HM Forces"
    },
    "Claimant_HM_Forces_Enlisted__c": {
        "tab": "history",
        "section": "history-1",
        "label": "UK & Abroad › HM Forces"
    },
    "Claimant_HM_Forces_Discharged_Where__c": {
        "tab": "history",
        "section": "history-1",
        "label": "UK & Abroad › HM Forces"
    },
    "Claimant_HM_Forces_Service_No__c": {
        "tab": "history",
        "section": "history-1",
        "label": "UK & Abroad › HM Forces"
    },
    "Claimant_HM_Forces_Service__c": {
        "tab": "history",
        "section": "history-1",
        "label": "UK & Abroad › HM Forces"
    },
    "Claimant_HM_Forces_Discharged__c": {
        "tab": "history",
        "section": "history-1",
        "label": "UK & Abroad › HM Forces"
    },
    "Claimant_HM_Forces_Regiment__c": {
        "tab": "history",
        "section": "history-1",
        "label": "UK & Abroad › HM Forces"
    },
    "Claimant_HM_Forces_Rank__c": {
        "tab": "history",
        "section": "history-1",
        "label": "UK & Abroad › HM Forces"
    },
    "Ever_Self_Employed_UK_after_1978__c": {
        "tab": "history",
        "section": "history-2",
        "label": "UK & Abroad › NI contributions"
    },
    "Work_In_UK_during_2_years__c": {
        "tab": "history",
        "section": "history-2",
        "label": "UK & Abroad › NI contributions"
    },
    "Ever_Pay_Reduced_UK_nino__c": {
        "tab": "history",
        "section": "history-2",
        "label": "UK & Abroad › NI contributions"
    },
    "Claimant_nationality__c": {
        "tab": "history",
        "section": "history-3",
        "label": "UK & Abroad › Abroad"
    },
    "Is_Your_Partner_Currently_Get_Pension__c": {
        "tab": "history",
        "section": "history-3",
        "label": "UK & Abroad › Abroad"
    },
    "isYourPartnerCurrentlyGetPensionText__c": {
        "tab": "history",
        "section": "history-3",
        "label": "UK & Abroad › Abroad"
    },
    "DocuSign_Date__c": {
        "tab": "dwp",
        "section": "dwp-0",
        "label": "DWP › Sent to DWP"
    },
    "Big_Envelop_Posted_Date__c": {
        "tab": "dwp",
        "section": "dwp-0",
        "label": "DWP › Sent to DWP"
    },
    "Process_Claim_Email_Date__c": {
        "tab": "dwp",
        "section": "dwp-0",
        "label": "DWP › Sent to DWP"
    },
    "Tracking_Number__c": {
        "tab": "dwp",
        "section": "dwp-0",
        "label": "DWP › Sent to DWP"
    },
    "Big_Envelop_Tracking_Number__c": {
        "tab": "dwp",
        "section": "dwp-0",
        "label": "DWP › Sent to DWP"
    },
    "Award_Amount_GBP__c": {
        "tab": "dwp",
        "section": "dwp-1",
        "label": "DWP › DWP answer"
    },
    "DWP_Payment_Date__c": {
        "tab": "dwp",
        "section": "dwp-1",
        "label": "DWP › DWP answer"
    },
    "Award_Amount__c": {
        "tab": "dwp",
        "section": "dwp-1",
        "label": "DWP › DWP answer"
    },
    "Pension_Claiming_from_Today__c": {
        "tab": "pension",
        "section": "pension-0",
        "label": "Pension › State Pension"
    },
    "Pension_Deferred_Pension__c": {
        "tab": "pension",
        "section": "pension-0",
        "label": "Pension › State Pension"
    },
    "Pension_Work_After_Pension_Age__c": {
        "tab": "pension",
        "section": "pension-0",
        "label": "Pension › State Pension"
    },
    "Pension_Start_Date__c": {
        "tab": "pension",
        "section": "pension-0",
        "label": "Pension › State Pension"
    },
    "Paid_Interval__c": {
        "tab": "pension",
        "section": "pension-0",
        "label": "Pension › State Pension"
    },
    "Pension_Imprisoned_Since_Pension_Age__c": {
        "tab": "pension",
        "section": "pension-0",
        "label": "Pension › State Pension"
    },
    "Claimant_State_Pension__c": {
        "tab": "pension",
        "section": "pension-1",
        "label": "Pension › Benefits ever claimed"
    },
    "Claimant_Widows_Benefit__c": {
        "tab": "pension",
        "section": "pension-1",
        "label": "Pension › Benefits ever claimed"
    },
    "Claimant_is_Waiting_Uk_Benefits__c": {
        "tab": "pension",
        "section": "pension-1",
        "label": "Pension › Benefits ever claimed"
    },
    "Claimant_Graduated_Retirement_Benefit__c": {
        "tab": "pension",
        "section": "pension-1",
        "label": "Pension › Benefits ever claimed"
    },
    "Claimant_Bereavement_Benefit__c": {
        "tab": "pension",
        "section": "pension-1",
        "label": "Pension › Benefits ever claimed"
    },
    "Claimant_is_Waiting_Uk_Benefits_text__c": {
        "tab": "pension",
        "section": "pension-1",
        "label": "Pension › Benefits ever claimed"
    },
    "Age_Pension_now_or_next_year__c": {
        "tab": "pension",
        "section": "pension-2",
        "label": "Pension › Australia"
    },
    "Are_you_self_assessed_for_tax__c": {
        "tab": "pension",
        "section": "pension-3",
        "label": "Pension › Tax & UK property"
    },
    "Do_you_own_rent_any_UK_property__c": {
        "tab": "pension",
        "section": "pension-3",
        "label": "Pension › Tax & UK property"
    },
    "Do_you_have_an_accountant__c": {
        "tab": "pension",
        "section": "pension-3",
        "label": "Pension › Tax & UK property"
    },
    "Accountant_Name__c": {
        "tab": "pension",
        "section": "pension-4",
        "label": "Pension › Accountant"
    },
    "Accountant_Address__c": {
        "tab": "pension",
        "section": "pension-4",
        "label": "Pension › Accountant"
    },
    "Accountant_City__c": {
        "tab": "pension",
        "section": "pension-4",
        "label": "Pension › Accountant"
    },
    "Accountant_PostCode__c": {
        "tab": "pension",
        "section": "pension-4",
        "label": "Pension › Accountant"
    },
    "Accountant_Phone__c": {
        "tab": "pension",
        "section": "pension-4",
        "label": "Pension › Accountant"
    },
    "Accountant_Address_2__c": {
        "tab": "pension",
        "section": "pension-4",
        "label": "Pension › Accountant"
    },
    "Accountant_State_Name__c": {
        "tab": "pension",
        "section": "pension-4",
        "label": "Pension › Accountant"
    },
    "Accountant_Country_Name__c": {
        "tab": "pension",
        "section": "pension-4",
        "label": "Pension › Accountant"
    },
    "Owns_This_Account__c": {
        "tab": "bank",
        "section": "bank-0",
        "label": "Bank › Account holder"
    },
    "Bank_Account_Owner_Email__c": {
        "tab": "bank",
        "section": "bank-0",
        "label": "Bank › Account holder"
    },
    "Bank_Account_Owner_Name__c": {
        "tab": "bank",
        "section": "bank-0",
        "label": "Bank › Account holder"
    },
    "Bank_Name__c": {
        "tab": "bank",
        "section": "bank-1",
        "label": "Bank › Account"
    },
    "Bank_IBAN__c": {
        "tab": "bank",
        "section": "bank-1",
        "label": "Bank › Account"
    },
    "Bank_Account__c": {
        "tab": "bank",
        "section": "bank-1",
        "label": "Bank › Account"
    },
    "Bank_Account_Type__c": {
        "tab": "bank",
        "section": "bank-1",
        "label": "Bank › Account"
    },
    "Bank_BIC__c": {
        "tab": "bank",
        "section": "bank-1",
        "label": "Bank › Account"
    },
    "Bank_Sort_Code__c": {
        "tab": "bank",
        "section": "bank-1",
        "label": "Bank › Account"
    },
    "Bank_Address__c": {
        "tab": "bank",
        "section": "bank-2",
        "label": "Bank › Bank address"
    },
    "Bank_Post_Code__c": {
        "tab": "bank",
        "section": "bank-2",
        "label": "Bank › Bank address"
    },
    "Bank_City__c": {
        "tab": "bank",
        "section": "bank-2",
        "label": "Bank › Bank address"
    },
    "Bank_Country__c": {
        "tab": "bank",
        "section": "bank-2",
        "label": "Bank › Bank address"
    },
    "Bank_Country_Code__c": {
        "tab": "bank",
        "section": "bank-2",
        "label": "Bank › Bank address"
    },
    "Agent_Making_Sale__c": {
        "tab": "payment",
        "section": "payment-0",
        "label": "Sale & Payment › Sale"
    },
    "How_did_you_hear_about_us__c": {
        "tab": "payment",
        "section": "payment-0",
        "label": "Sale & Payment › Sale"
    },
    "Sales_Call_A_Date__c": {
        "tab": "payment",
        "section": "payment-0",
        "label": "Sale & Payment › Sale"
    },
    "Val_Call_Booked_Date__c": {
        "tab": "payment",
        "section": "payment-0",
        "label": "Sale & Payment › Sale"
    },
    "Validation_Agent__c": {
        "tab": "payment",
        "section": "payment-0",
        "label": "Sale & Payment › Sale"
    },
    "Val_Form_Complete__c": {
        "tab": "payment",
        "section": "payment-0",
        "label": "Sale & Payment › Sale"
    },
    "Sales_Call_B_Date__c": {
        "tab": "payment",
        "section": "payment-0",
        "label": "Sale & Payment › Sale"
    },
    "Deposit_Paid__c": {
        "tab": "payment",
        "section": "payment-1",
        "label": "Sale & Payment › Payment"
    },
    "Paid_Date__c": {
        "tab": "payment",
        "section": "payment-1",
        "label": "Sale & Payment › Payment"
    },
    "Stripe_Customer_Id__c": {
        "tab": "payment",
        "section": "payment-1",
        "label": "Sale & Payment › Payment"
    },
    "LatestCharge__c": {
        "tab": "payment",
        "section": "payment-1",
        "label": "Sale & Payment › Payment"
    },
    "Deposit_Payment_Date__c": {
        "tab": "payment",
        "section": "payment-1",
        "label": "Sale & Payment › Payment"
    },
    "Payment_Method__c": {
        "tab": "payment",
        "section": "payment-1",
        "label": "Sale & Payment › Payment"
    },
    "Stripe_Transaction_Id__c": {
        "tab": "payment",
        "section": "payment-1",
        "label": "Sale & Payment › Payment"
    },
    "GoCardless_Mandate_Id__c": {
        "tab": "payment",
        "section": "payment-2",
        "label": "Sale & Payment › Direct Debit"
    },
    "GoCardless_Bank_Account_Id__c": {
        "tab": "payment",
        "section": "payment-2",
        "label": "Sale & Payment › Direct Debit"
    },
    "GoCardless_Customer_Id__c": {
        "tab": "payment",
        "section": "payment-2",
        "label": "Sale & Payment › Direct Debit"
    },
    "CreatedById": {
        "tab": "system",
        "section": "system-0",
        "label": "System › Record"
    },
    "CreatedDate": {
        "tab": "system",
        "section": "system-0",
        "label": "System › Record"
    },
    "OwnerId": {
        "tab": "system",
        "section": "system-0",
        "label": "System › Record"
    },
    "LastModifiedById": {
        "tab": "system",
        "section": "system-0",
        "label": "System › Record"
    },
    "LastModifiedDate": {
        "tab": "system",
        "section": "system-0",
        "label": "System › Record"
    },
    "Is_envelope_created__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "FTP_Claim_Created_Send_Date__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "FTP_Claim_Created_ZIP_Error__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "Claim_Full_Form_ZIP_for_UPLOAD__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "FTP_Claim_Full_Form_Error__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "Claim_Created_ZIP_for_UPLOAD__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "FTP_Claim_Created_Error__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "Is_Test_Claim__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "FTP_Claim_Full_Form_Created_Send_Date__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "FTP_Claim_Full_Form_ZIP_Error__c": {
        "tab": "system",
        "section": "system-1",
        "label": "System › Printing house upload"
    },
    "X1st_Follow_Up_Call__c": {
        "tab": "system",
        "section": "system-2",
        "label": "System › E-sign follow-up calls"
    },
    "X2nd_Follow_Up_Call__c": {
        "tab": "system",
        "section": "system-2",
        "label": "System › E-sign follow-up calls"
    },
    "X3rd_Follow_Up_Call__c": {
        "tab": "system",
        "section": "system-2",
        "label": "System › E-sign follow-up calls"
    },
    "Call_Follow_Up_Change_User__c": {
        "tab": "system",
        "section": "system-2",
        "label": "System › E-sign follow-up calls"
    },
    "X1st_Esign_Follow_Up_Call_Changed_Date__c": {
        "tab": "system",
        "section": "system-2",
        "label": "System › E-sign follow-up calls"
    },
    "X2nd_Esign_Follow_Up_Call_Changed_Date__c": {
        "tab": "system",
        "section": "system-2",
        "label": "System › E-sign follow-up calls"
    },
    "X3rd_Esign_Follow_Up_Call_Changed_Date__c": {
        "tab": "system",
        "section": "system-2",
        "label": "System › E-sign follow-up calls"
    },
    "Verification_Status__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Verified_Reference__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Data8_Last_validation_date__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Partner_Verification_Status__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Partner_Verified_Reference__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Partner_Address_Validated__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Verification_Details__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Was_Cleansed__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Data8_Validation_result__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Partner_Verification_Details__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Partner_Was_Cleansed__c": {
        "tab": "system",
        "section": "system-3",
        "label": "System › Address checks"
    },
    "Claim_Type__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Validation_Agent_Name__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Stage_1_Pack_Posted_Date__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Form_Agent_URL__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Agent_Form_Complete__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "IPC1394_Required__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "What_is_this_number__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Claimant_self_Employed_UK__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Claimant_hasNino__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "BSB_Number__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Has_Irish_Current_Account__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Confirmed_Date__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Has_Utility_Bill__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Contact_Type__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Last_Contact_Date__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Date_Since_Contact__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Days_Since_Contact__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Helper_Name__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "PPS_NINO__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Full_Current_Ad__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Current_Address_Abroad_Country__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Partner_Country_Code__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Accountant_Country_Code__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Bank_Account_Number_formula__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "BR1_Snapshot_JSON__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Email_Text__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Missing_Info__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Stage_1_Pack_Tracking_Number__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Short_Agent_Link__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Validation_Form_Complete__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "IPC1349_Required__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Preferred_Channel__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Claimant_Ever_Paid_Married_Woman_s_Stam__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Partner_Has_Nino__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Age_Pension_AUS__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Opening_Status__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Has_Photo_ID__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Close_CRM_Lead_Id__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Who__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Last_Contact_At__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Days_Since_Last_Contact__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Days_Since_Contact_Data__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Customer__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Partner_Full_Name__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Current_Address_Abroad__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Current_Address_Abroad_State__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Partner_State_Code__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Accountant_State_Code__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Bank_Sort_Code_formula__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    },
    "Personal_Details_Form_Link__c": {
        "tab": "system",
        "section": "system-4",
        "label": "System › Rarely used"
    }
};