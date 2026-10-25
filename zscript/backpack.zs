// ------------------------------------------------------------
// Backpack
// ------------------------------------------------------------

//	Each entry in the storage item is single string, a comma-separated list.
//	An HDWeapon is "classname,wepstat0,...wepstat31,icon,bulk". 1 weapon = 1 entry.
//	All other items are 1 entry = 1 class.
//	An HDMagAmmo is "classname,amount1,amount2,..." tracking each mag.
//	All else is "classname,amount".
//
//	The main functions to look out for when modding are as follows:
//
//	Extract(int itemindex, int flags, int amt)
//		- creates an item as though it were pulled out of the backpack
//		- you can flag it so that it doesn't remove the backpack entry,
//		  creating a duplicate instead
//		- amount is only supported for non-mag items,
//		  use a for loop for weapons and mags
//
//	Insert(inventory thisitem, int amt)
//		- takes an existing actor and puts it in the backpack
//		- depletes and destroys the actor as applicable
//		- fails if bulk exceeded
//
//	Add(string toadd)
//		- adds an item to the backpack
//		- parameter taken is the same format as stored,
//		  e.g. Add("HD4mMag,51,51,51") to add 3 unopened ZM mags
//		- if a non-weapon of the same class exists, expands on existing entry
//		- if a weapon of the same class exists, slots it next to that weapon
//		- does NOT check for bulk, can go over capacity;
//		  therefore make sure players go through Insert()!
//
//	Count(string type)
//		- returns number of item type, excluding subcontainers
//
//	CanFitInThisContainer(class<inventory> itemtype)
//		- virtual function, change params as you please
//		- sets out non-negotiable criteria to allow placement
//		- unlike bulk this IS checked in Add()
//
//	HDStorageItemList.CanAdd(class<inventory> itemtype)
//		- virtual function, determines if an item can be a candidate when
//		  deciding what to randomly populate a found container with
//		- creates a new HDStorageItemList class and reference it using
//		  the parameter in any RandomContents() call
//
//	GetSubContainerIndex(int itemindex)
//		- if the item at itemindex is inside a container inside the main
//		  container, returns the index of that container
//		- if the item is in multiple nested containers, this returns the
//		  container it is immediately inside
//		- returns -1 if it's only in the main container
//		- returns -2 if itemindex out of bounds
//
//  GetThisItemBulk(int itemindex)
//		- returns total bulk of any line item, including inside subcontainers
//		- if it's a container, output includes its contents
//
//	RecalculateBulk()
//		- if all else fails or would require an unmaintainable bowl of
//		  spaghetti, call this to recount everything
//		- if you've *really* gone crazy with the contents and multiple
//		  subcontainers have been changed at once, call this again
//		  so that surcontainers can access updated values
//
//	KeepItRare(class<inventory> this)
//		- if the randomizer hits this item, it will roll again,
//		  making these items much more rare in wild backpacks than others.
//
//	Also check out the BFG and Liberator code for examples of how to use
//	HDWeapon.PersistentConsolidate() for backpack-placement-agnostic actions.


enum HDStorageItemStats{
	SISTAT_ININDEX=1,
	SISTAT_SELINDEX=2,
	SISTAT_HOWMANY=3,
	SISTAT_SCROLL=4,

	SI_WEPICONSLOT=HDWEP_STATUSSLOTS+1,
	SI_WEPBULKSLOT=HDWEP_STATUSSLOTS+2,
	SI_MAXROWS=10,
	SI_SCROLLCYCLE=(2<<9),
}
class HDStorageItem:HDWeapon abstract{
    private transient CVar bvel;

	array<string> items;
	double itembulk;

	double maxcapacity;property maxcapacity:maxcapacity;
	int maxbunch;property maxbunch:maxbunch;

	//empty container still weighs something and takes up space
	double minbulk;property minbulk:minbulk;
	override double WeaponBulk(){
		return ContainerBulk(itembulk*0.9);
	}

	//how much space it takes inside another container
	//if we don't do this then things nested inside multiple containers
	//eventually have almost no bulk at all
	virtual double ContainerBulk(
		double it
	)const{
		return max(minbulk,minbulk*0.4+it);
	}

	//called whenever an item was successfully inserted into the container
	//in case child classes want to add additional effects
	virtual void OnInsert(inventory item){}

	//called whenever an item was successfully extracted from the container
	//in case child classes want to add additional effects
	virtual void OnExtract(inventory item, vector3 pos){}


	override void Tick(){
		super.Tick();
		if(
			!isFrozen()
			&&itembulk>maxcapacity
		)DumpItems();
	}


	// spawn an item
	inventory Extract(
		int itemindex,
		int amt=1,
		int flags=0
	){
		if(
			itemindex<0
			||itemindex>=items.size()
		)return null;
		array<string> strs;strs.clear();

		// skip sub-stored items
		int iterationsallowed=items.size();  // VM abort "good", CTD bad
		while(items[itemindex].left(2)=="--"&&iterationsallowed>0){
			itemindex++;
			iterationsallowed--;
			if(itemindex>=items.size())itemindex=0;
		}

		items[itemindex].split(strs,",");
		let epos=ExtractPos();
		let ddd=spawn(strs[0],epos);

		if(owner)ddd.vel=(owner.vel.xy+rotatevector((1,0),owner.angle),owner.vel.z+0.6);
		else ddd.vel=vel;

		let hdw=HDWeapon(ddd);
		let hdm=HDMagAmmo(ddd);
		let hdp=HDPickup(ddd);

		if(!!hdw){
			hdw.bdontdefaultconfigure=true;
			strs.delete(0);	//delete name so wepstat numbers line up
			for(int i=0;i<HDWEP_STATUSSLOTS;i++){
				hdw.weaponstatus[i]=strs[i].toInt();
			}

			//record this in case it's a storageitem
			double wpbulk=strs[strs.size()-1].toDouble();

			//no fancy checks, each array item always = 1 weapon actor
			itembulk-=wpbulk;
			items.delete(itemindex);

			//populate storageitem with sub-stored as appropriate
			let hdsi=HDStorageItem(hdw);
			if(hdsi){
				string prefix="--"..hdsi.weaponstatus[SISTAT_ININDEX].."--";
				int pl=prefix.length();
				for(int i=0;i<items.size();i++){
					if(items[i].left(pl)==prefix){
						hdsi.items.Push(items[i].mid(pl));
						items.delete(i);
						i--;
					}
				}
				hdsi.RecalculateBulk();
			}

			if(!!owner){
				if(hdw.bdroptranslation)hdw.translation=owner.translation;
				hdw.target=owner;

				string strszero=hdw.getclassname();
				if(
					IndexOf(strszero.makelower())<0
					&&(
						!owner.findinventory(strszero)
						||strszero==getclassname()  //don't count itself
					)
				){
					selectableitems.delete(selectableitems.find(strszero.makelower()));
				}
			}
			OnExtract(hdw,epos);
			return hdw;
		}else if(!!hdm){
			if(strs.size()>=2){
				hdm.mags[0]=strs[strs.size()-1].toInt();
			}

			// remove one mag count from the list
			string oldstr=items[itemindex];
			if(strs.size()>2){
				items[itemindex]=oldstr.left(oldstr.rightindexof(","));
			}
			else items.delete(itemindex);
			itembulk-=hdm.getmagbulk(FinalNumber(oldstr));

			if(!!owner){
				if(hdm.bdroptranslation)hdm.translation=owner.translation;
				if(
					IndexOf(strs[0])<0
					&&!owner.findinventory(strs[0])
				){
					selectableitems.delete(selectableitems.find(strs[0]));
				}
			}
			OnExtract(hdm,epos);
			return hdm;
		}else if(!!hdp){
			int curramt=strs[1].toInt();
			amt=clamp(amt,1,curramt);	//take only what's available
			hdp.amount=amt;

			// reduce the item count
			int remaining=curramt-amt;
			if(remaining<1)items.delete(itemindex);
			else items[itemindex]=strs[0]..","..remaining;
			itembulk-=amt*hdp.bulk;

			if(!!owner){
				if(hdp.bdroptranslation)hdp.translation=owner.translation;
				if(
					IndexOf(strs[0])<0
					&&!owner.findinventory(strs[0])
				){
					selectableitems.delete(selectableitems.find(strs[0]));
				}
			}
			OnExtract(hdp,epos);
			return hdp;
		}
		return null;
	}

	// take existing pickup/weapon, add it and destroy original if depleted
	bool Insert(
		inventory thisitem,
		int amt=1
	){
		//self-insertion? go fuck yourself.
		if(thisitem==self)return false;

		let hdw=HDWeapon(thisitem);
		let hdm=HDMagAmmo(thisitem);
		let hdp=HDPickup(thisitem);
		if(
			(!hdp&&!hdw)
			||!ThisCanFitInThisContainer(thisitem)
		)return false;

		string inserted=thisitem.GetClassName();
		inserted=inserted.makelower();
		int existing=indexof(inserted);
		if(hdw){
			let hdsi=HDStorageItem(hdw);
			bool subcontainer=hdsi&&hdsi.items.size()>0;

			double wbulk=hdsi?hdsi.ContainerBulk(hdsi.itembulk):hdw.WeaponBulk();
			if(maxcapacity-itembulk<wbulk)return false;

			string finalinsert=inserted;

			int sci=-1;  //subcontainer index
			if(subcontainer){
				// find first free index number
				bool alreadyused=false;
				do{
					sci++;  //if sci starts at 1, the first usable number is zero
					string sss="--"..sci.."--";
					alreadyused=false;
					for(int j=0;j<items.size();j++){
						if(items[j].left(sss.length())==sss){
							alreadyused=true;
							break;
						}
					}
				}while(
					alreadyused
					&&sci<items.size()	//safeguard against infinite loops
				);

				// track stored items within stored items
				if(subcontainer){
					for(int j=0;j<hdsi.items.size();j++){
						items.push("--"..sci.."--"..hdsi.items[j]);
					}
				}
			}
			// assign the subcontainer index (empties get -1)
			if(hdsi)hdsi.weaponstatus[SISTAT_ININDEX]=sci;

			// put together the string
			for(int i=0;i<HDWEP_STATUSSLOTS;i++){
				finalinsert=finalinsert..","..hdw.weaponstatus[i];
			}
			if(Add(finalinsert..","..hdw.GetPickupSprite()..","..wbulk)){
				OnInsert(hdw);
				owner.DropInventory(hdw);  //trigger fetching from spares
				hdw.destroy();
				return true;
			}

		}else if(hdm){
			hdm.SyncAmount();	//just in case
			int loaded=hdm.mags[hdm.mags.size()-1];
			if(maxcapacity-itembulk>=hdm.GetMagBulk(loaded)){
				if(Add(inserted..","..loaded)){
					OnInsert(hdm);
					hdm.mags.pop();
					if(hdm.mags.size()<1)hdm.destroy();
					else hdm.amount--;
					return true;
				}
			}
		}else if(hdp){
			amt=hdp.owner?min(amt,hdp.amount):hdp.amount;
			double canfit=0;
			if(hdp.bulk>0){
				canfit=(maxcapacity-itembulk)/hdp.bulk;
				if(amt>canfit)amt=int(canfit);
			}
			if(Add(inserted..","..amt)){
				OnInsert(hdp);
				hdp.amount-=amt;
				if(hdp.amount<1)hdp.destroy();
				return true;
			}
		}
		return false;
	}


	// add an item
	bool Add(
		string toadd
	){
		toadd=toadd.makelower();	//*some* checks seem to be case sensitive, lower them all!
		string itemname=toadd.left(toadd.indexof(","));
		class<inventory> itemclass=itemname;

		if(!CanFitInThisContainer(itemclass))return false;

		bool isweapon=(itemclass is "HDWeapon");
		bool ismag=(itemclass is "HDMagAmmo");
		bool ispickup=(!ismag && (itemclass is "HDPickup"));

		//check if interaction list already contains this kind of item
		if(selectableitems.find(itemname)==selectableitems.size())
		selectableitems.insert(0,itemname);

		//check if already contains this kind of item
		int existing=indexof(itemname);

		if(isweapon){
			items.insert(max(0,existing),toadd);	//add weapons next to their own kind
			itembulk+=toadd.mid(toadd.rightindexof(",")+1).toDouble();
			Select(itemname);
			return true;
		}

		//add mags as additional counts
		if(ismag){
			string addmags=toadd.mid(toadd.indexof(","));
			if(existing<0)items.insert(0,toadd);
			else items[existing]=items[existing]..addmags;

			array<string> mags;mags.clear();
			addmags.mid(1).split(mags,",");
			let mmm=HDMagAmmo(getdefaultbytype(itemclass));
			for(int i=0;i<mags.size();i++){
				itembulk+=mmm.GetMagBulk(mags[i].toInt());
			}
			Select(itemname);
			return true;
		}

		//for all else, add to existing amount
		if(ispickup){
			int toaddint=FinalNumber(toadd);
			if(toaddint<1)return false;
			if(existing<0)items.insert(0,toadd);
			else items[existing]=itemname..","..(FinalNumber(items[existing])+toaddint);
			itembulk+=toaddint*HDPickup(getdefaultbytype(itemclass)).bulk;
			Select(itemname);
			return true;
		}

		return false;
	}


	//haphazardly dump shit out
	void DumpItems(){
        if(!bvel) bvel = CVar.GetCVar('tt_bvel', owner.player);
		int i=weaponstatus[SISTAT_SELINDEX];
		if(selectableitems.size()>i){
			let iii=selectableitems[i];
			int jjj=IndexOf(iii);
			if(jjj<0)jjj=0;
			let eee=Extract(jjj,maxbunch);
			if(!!eee){
				if(bvel.getBool())eee.vel+=(frandom(-1,1),frandom(-1,1),frandom(0,0.5));
				A_StartSound("weapons/pocket",CHAN_WEAPON);
			}else{
				for(int j=0;j<items.size();j++){
					let k=items[j];
					if(k.left(1)!="-"){
						k=k.left(k.indexof(","));
						Select(k);
					}
				}
			}
		}
		SanitizeSelectionIndex();
	}


	//brute-force a bulk count
	double RecalculateBulk(){
		double total=0;
		//go in reverse order so sub-subcontainers are updated first
		for(int i=items.size()-1;i>=0;i--){
			bool subcontained=items[i].left(2)=="--";
			let subcontainer=(class<HDStorageItem>)(ItemClassAndPrefix(i));

			double gib=(!subcontained||subcontainer)?GetThisItemBulk(i):0;

			//update subcontainers in case anything's changed
			if(subcontainer){
				string sss=items[i];
				sss=sss.left(sss.rightindexof(",")+1)..gib;
			}

			//don't add subcontainer contents - already accounted for in subcontainer bulk
			if(!subcontained)total+=gib;
		}
		itembulk=total;
		return total;
	}


// informational


	//get the final number in a comma'd list
	clearscope int FinalNumber(
		string input
	){
		return input.Mid(input.RightIndexOf(",")+1).toInt();
	}

	// look for an item in the backpack by name
	clearscope int IndexOf(
		string itemname
	){
		itemname=itemname.makelower();
		int naml=itemname.length();
		for(int i=0;i<items.size();i++){
			string s=items[i];
			if(
				s.left(naml)==itemname
				&&s.charat(naml)==","	//whole name must match
			)return i;
		}
		return -1;
	}
	clearscope int LastIndexOf(
		string itemname
	){
		int naml=itemname.length();
		for(int i=items.size()-1;i>=0;i--){
			string s=items[i];
			if(
				s.left(naml)==itemname
				&&s.charat(naml)==","
			)return i;
		}
		return -1;
	}

	//count how many of something there is
	clearscope int Count(
		string type
	){
		type=type.makeLower();
		let hdw=(class<HDWeapon>)(type);
		let hdm=(class<HDMagAmmo>)(type);
		let hdp=(class<HDPickup>)(type);

		if(hdw){
			int count=0;
			for(int i=0;i<items.size();i++){
				if(items[i].left(type.length())==type)count++;
			}
			return count;
		}
		int iii=IndexOf(type);
		if(iii<0)return 0;

		if(hdm){
			array<string> gbg;
			items[iii].split(gbg,",");
			return gbg.size()-1;
		}else if(hdp){
			return FinalNumber(items[iii]);
		}

		return 0;
	}


	//get the total bulk of one line item
	clearscope double GetThisItemBulk(
		int itemindex
	){
		let iii=items[itemindex];
		string sss,ssc;
		[sss,ssc]=ItemClassAndPrefix(itemindex);

		let hds=(class<HDStorageItem>)(sss);
		let hdw=(class<HDWeapon>)(sss);
		let hdm=(class<HDMagAmmo>)(sss);
		let hdp=(class<HDPickup>)(sss);

		if(hds){
			double newsibulk;
			string sindex=iii.mid(ssc.length());
			for(int i=0;i<(SISTAT_ININDEX+1);i++){
				sindex=sindex.mid(sindex.indexof(",")+1);
			}
			sindex=ssc.."--"..sindex.left(sindex.indexof(",")).."--";
			if(hd_debug>1)console.printf("BPINDEX  "..sindex);
			for(int i=items.size()-1;i>0;i--){
				let ttt=items[i];
				if(ttt.indexof("-")!=0)break;	//finished subcontainee list
				if(
					ttt.indexof(sindex)==0
					&&ttt.mid(sindex.length()).left(2)!="--"  //don't do sub-subcontainees
				){
					double gib=GetThisItemBulk(i);
					if(hd_debug>1)console.printf(ttt.."   "..gib.."   "..HDStorageItem(getdefaultbytype(hds)).minbulk);
					newsibulk+=gib;
				}
			}
			return HDStorageItem(getdefaultbytype(hds)).ContainerBulk(newsibulk);
		}
		//incorporate into both recalc and insert
		//don't bother with extract for now

		if(hdw)return FinalNumber(iii);

		if(hdm){
			double total=0;
			array<string> mags;
			string mmm=iii.mid(iii.indexof(",")+1);
			mmm.split(mags,",");
			for(int j=0;j<mags.size();j++){
				total+=HDMagAmmo(getdefaultbytype(hdm)).GetMagBulk(mags[j].toInt());
			}
			return total;
		}

		if(hdp)return FinalNumber(iii)*HDPickup(getdefaultbytype(hdp)).bulk;

		return 0;
	}


	//trim params/amounts, return classname and subcontainer prefix
	clearscope string,string ItemClassAndPrefix(
		int index
	){
		if(index>=items.size())return "","";
		string inp=items[index];
		inp=inp.left(inp.IndexOf(","));
		int prefixindex=inp.RightIndexOf("--");	//can't search "-" or risk "Lib-Drum"
		if(prefixindex<0)return inp,"";
		prefixindex+=2;	//get the entire prefix
		return inp.mid(prefixindex),inp.left(prefixindex);
	}


	//check if an item can be added at all
	virtual clearscope bool CanFitInThisContainer(
		class<inventory> itemtype
	){
		let iii=getdefaultbytype(itemtype);
		let ppp=HDPickup(iii);
		let www=HDWeapon(iii);
		return
			!!iii
			&&!iii.bnointeraction
			&&(
				(ppp&&ppp.bfitsinbackpack)
				||(www&&www.bfitsinbackpack)
			)
		;
	}
	// sometimes particular instances of an item may vary
	virtual clearscope bool ThisCanFitInThisContainer(
		inventory item
	){
		let ppp=HDPickup(item);
		let www=HDWeapon(item);
		return
			!!item
			&&!item.bnointeraction
			&&(
				(ppp&&ppp.bfitsinbackpack)
				||(www&&www.bfitsinbackpack)
			)
		;
	}

	// get position in front of user to spawn extracted item
	virtual clearscope vector3 ExtractPos(){
		if(!owner)return (pos.x+frandom(-3,3),pos.y+frandom(-3,3),pos.z+frandom(18,24));
		return owner.pos+HDMath.GetGunPos(owner);
	}


	//takes an items entry at that index
	//returns the index of the sub-container it is immediately inside
	//call it a bunch of times if you want the whole chain
	//returns -1 if it's not in a subcontainer at all
	//returns -2 if itemindex out of bounds
	int GetSubContainerIndex(int itemindex){
		//returns -2 if itemindex out of bounds
		if(itemindex<0||itemindex>=items.size())return -2;

		let thisitem=items[itemindex];

		//returns -1 if it's not in a subcontainer at all
		if(thisitem.left(2)!="--")return -1;

		//get the subcontainer index
		string thisprefixnum=items[itemindex];
		thisprefixnum=thisprefixnum.left(thisprefixnum.rightindexof("--"));
		thisprefixnum=thisprefixnum.mid(thisprefixnum.rightindexof("--")+2);

		//get the final int
		//go through all items
		for(int i=0;i<items.size();i++){
			string clsn=ItemClassAndPrefix(i);
			if(!(class<HDStorageItem>)(clsn))continue;
			array<string>wpst;
			items[i].split(wpst,",");

			//grab the subcontainer index and compare
			//if they match, return the index
			if(wpst[SISTAT_ININDEX+1]==thisprefixnum){	//"+1" because of the classname
				return i;
			}
		}

		//debug: if nothing matches, return -1 and delete the prefix from the original item
		console.printf("ERROR: Item given prefix for nonexistent subcontainer. Prefix deleted and item moved into container proper.\n\n  "..thisitem);
		items[itemindex]=thisitem.mid(thisitem.rightindexof("--")+2);
		return -1;
	}


	// debug: dump raw entries into console
	clearscope string DumpData(){
		string bpc="";
		for(int i=0;i<items.size();i++){
			bpc=bpc.."\n  "..items[i];
		}
		if(bpc=="")bpc="Backpack is empty.";
		else bpc="Backpack contents:"..bpc;

		console.printf(bpc);
		return bpc;
	}




// loadout stuff

	override void loadoutconfigure(string loadlist){
		loadlist.replace(" ","");
		loadlist=loadlist.makelower();
		array<string> whichitem;
		loadlist.Split(whichitem,".",TOK_SKIPEMPTY);
		for(int i=0;i<whichitem.size();i++){
			string refid=whichitem[i].left(3);
			string params=whichitem[i].mid(3,whichitem[i].length());

			if(refid=="???"){
				RandomContents("HDStorageItemList",0.2,true);
				continue;
			}

			class<inventory> reff=HDHandlers.ParseRefID(refid);
			if(!reff){
				A_Log(StringTable.Localize("$LOADOUT_UNKNOWNCODE").."\cx"..refid.."\ca\"",true);
				continue;
			}

			let gdb=getdefaultbytype((class<inventory>)(reff));

			if(!CanFitInThisContainer(reff)){
				A_Log(gdb.gettag().." ("..refid..") cannot fit in a "..gettag()..".");
				continue;
			}

			//don't spawn if certain dmflags
			if(
				deathmatch  //sv_noarmor/health normally does nothing outside dm
				&&(
					(sv_noarmor&&gdb.bisarmor)
					||(sv_nohealth&&gdb.bishealth)
				)
			)continue;

			if(reff is "HDWeaponGiver"){
				let pg=HDWeaponGiver(spawn(reff,pos));
				if(pg){
					let pgg=pg.actualweapon;
					if(!pgg){
						pgg=pg.spawnactualweapon();
						pg.destroy();
					}
					if(pgg){
						if(owner&&owner.player)pgg.defaultconfigure(owner.player);
						Insert(pgg);
					}
				}
			}else if(reff is "HDPickupGiver"){
				let pg=HDPickupGiver(spawn(reff,pos));
				if(pg){
					let pgg=pg.actualitem;
					if(!pgg){
						pgg=pg.spawnactualitem();
						pg.destroy();
					}
					if(pgg)Insert(pgg);
				}
			}else if(reff is "HDWeapon"){
				let gdbw=HDWeapon(gdb);
				if(
					gdbw.bdebugonly
					&&hd_debug<=0
				){
					A_Log(StringTable.Localize("$LOADOUT_CODE").."\cx"..refid.."\ca\" ("..getdefaultbytype(reff).gettag()..StringTable.Localize("$LOADOUT_DEBUGONLY"),true);
					continue;
				}
				if(!gdbw.bfitsinbackpack){
					A_Log(StringTable.Localize("$LOADOUT_CODE").."\cx"..refid.."\ca\" ("..getdefaultbytype(reff).gettag()..StringTable.Localize("$LOADOUT_DEBUGONLY"),true);
					continue;
				}

				int thismany;
				if(gdbw.bignoreloadoutamount)thismany=1;
				else thismany=clamp(params.toint(),1,40);

				while(thismany>0){
					thismany--;
					hdweapon newwep;
					newwep=hdweapon(spawn(reff,pos));

					if(newwep){
						//clear any randomized garbage
						newwep.weaponstatus[0]=0;

						//apply the default based on user cvar first
						let onr=owner;
						if(!onr){
							//this is almost certainly happening while the
							//backpack has just spawned at the calling player's
							//position, immediately before it's acquired.
							for(int pl=0;pl<MAXPLAYERS;pl++){
								if(
									playeringame[pl]
									&&players[pl].mo
									&&players[pl].mo.player==players[pl]
									&&players[pl].mo.pos==pos
								){
									onr=players[pl].mo;
									break;
								}
							}
						}
						if(onr&&onr.player){
							newwep.defaultconfigure(onr.player);
						}

						//now apply the loadout input to overwrite the defaults
						newwep.loadoutconfigure(params);

						if(
							!Insert(newwep)
							&&onr
						){
							newwep.bno_auto_switch=true;
							newwep.actualpickup(onr);
						}
					}
				}
			}else{
				string toadd=reff.getclassname();
				toadd=toadd.makelower();
				int amt=clamp(params.toInt(),1,gdb.maxamount);
				let gdbm=HDMagAmmo(gdb);
				if(!!gdbm){
					for(int j=0;j<amt;j++){
						toadd=toadd..","..gdbm.maxperunit;
					}
				}else{
					toadd=toadd..","..amt;
				}
				Add(toadd);
			}
		}
		RecalculateBulk();
	}


	void RandomContents(
		class<HDStorageItemList> listclass,
		double proportion,
		bool fromloadout
	){HDStorageItemList.RandomContents(self,listclass,proportion,fromloadout);}



// display/UI stuff

	override string GetHelpText(){
		int seli=weaponstatus[SISTAT_SELINDEX];
		bool ssss=
			seli>=0
			&&selectableitems.size()>seli
			&&(class<HDPickup>)(selectableitems[seli])
			&&!(class<HDMagAmmo>)(selectableitems[seli])
		;
		LocalizeHelp();
		return LWPHELP_FIRE.."/"..LWPHELP_ALTFIRE..StringTable.Localize("$BPWH_PNI")
		..LWPHELP_FIREMODE.."+"..LWPHELP_UPDOWN..StringTable.Localize("$BPWH_FMODPUD")
		..(
			ssss?
			LWPHELP_ZOOM.."+"..LWPHELP_UPDOWN..StringTable.Localize("$BPWH_ZPF")
			:""
		)
		..LWPHELP_RELOAD..StringTable.Localize("$BPWH_RELOAD")
		..LWPHELP_UNLOAD..StringTable.Localize("$BPWH_UNLOAD")
		..LWPHELP_DROPONE..StringTable.Localize("$BPWH_DROPO")
		..LWPHELP_ALTRELOAD..StringTable.Localize("$BPWH_ALTRELOAD");
	}


	override bool IsBeingWorn(){return true;}
	override int GetSbarNum(){
			int ii=int(itembulk);
			let sb=HDStatusBar(statusbar);
			if(sb){
				int mmm=int(maxcapacity);
				int iii=mmm-ii;
				if(iii<(mmm>>1)){
					if(iii<(mmm>>2))sb.savedcolour=Font.CR_RED;
					else sb.savedcolour=Font.CR_ORANGE;
				}else sb.savedcolour=Font.CR_OLIVE;
			}
			return ii;
		}
	override int DisplayAmount(){
		let sb=HDStatusBar(statusbar);
		if(sb)sb.savedcolour=Font.CR_DARKGRAY;
		return int(maxcapacity);
	}
	
	array<string> selectableitems;


	void Select(
		string itemname
	){
		itemname=itemname.makelower();
		weaponstatus[SISTAT_SELINDEX]=selectableitems.find(itemname);
		SanitizeSelectionIndex();
	}
	void SanitizeSelectionIndex(int offset=0){
		int sil=weaponstatus[SISTAT_SELINDEX]+offset;
		if(sil>=selectableitems.size())sil=0;
		else if(sil<0)sil=selectableitems.size()-1;
		weaponstatus[SISTAT_SELINDEX]=sil;
		if(offset){
			weaponstatus[SISTAT_HOWMANY]=1;
			SetHelpText();
		}else weaponstatus[SISTAT_HOWMANY]=clamp(weaponstatus[SISTAT_HOWMANY],1,maxbunch);

		UpdateHudStuff();
	}
	void UpdateSelected(){
		selectableitems.clear();
		for(int i=0;i<items.size();i++){
			let iii=items[i];
			if(iii.left(2)=="--")continue;
			iii=iii.left(iii.indexof(","));
			if(selectableitems.find(iii)==selectableitems.size()){
				selectableitems.push(iii);
			}
		}
		if(!!owner){
			for(inventory item=owner.inv;item!=null;item=item.inv){
				if(item==self)continue;
				string iii=item.getclassname();iii=iii.makelower();
				if(
					item!=self
					&&CanFitInThisContainer((class<inventory>)(iii))
					&&selectableitems.find(iii)==selectableitems.size()
				){
					selectableitems.push(iii);
				}
			}
		}
		SanitizeSelectionIndex();
	}

	string selectedicon;
	bool selectedicontranslate;
	vector2 selectediconscale;
	string onpersonicon;
	bool onpersonicontranslate;
	vector2 onpersoniconscale;
	string selectablenames[SI_MAXROWS];
	string selectablebps[SI_MAXROWS];
	string selectableops[SI_MAXROWS];
	string swapamt;
	int subcontainerbulk;
	void UpdateHudStuff(){
		if(!owner)return;

		int sels=selectableitems.size();
		if(sels<1){
			selectedicon="";
			onpersonicon="";
			selectablenames[0]="";
			subcontainerbulk=-1;
			return;
		}

		// we need to get, in descending order of priority:
		//  weapon pickup sprite; mag pickup sprite; icon; spawn state pickup sprite
		// and no function can take both an actual actor and getdefaultbytype.
		if(weaponstatus[SISTAT_SELINDEX]<sels){
			string sel=selectableitems[weaponstatus[SISTAT_SELINDEX]];
			textureid ddi;
			string dds="";
			vector2 ddv=(2.,2.4);
			swapamt="";

			let item=owner.findinventory(sel);
			if(
				!!item
				&&item!=self
			){
				let hdw=hdweapon(item);
				let hdm=hdmagammo(item);
				if(!!hdw){
					dds=hdw.GetPickupSprite();
				}else if(
					hdm
					&&hdm.mags.size()	//TakeMag() does not call destroy(), can be zero!
				){
					double scc;
					string gbg1;name gbg2;
					[dds,gbg1,gbg2,scc]=hdm.getmagsprite(hdm.mags[hdm.mags.size()-1]);
					ddv*=scc;
				}else{
					swapamt="\cu<->: \cj";
					ddi=item.icon;
					if(!!ddi)dds=texman.getname(ddi);
				}
				if(dds==""){
					let ddsp=item.spawnstate;
					if(ddsp!=null)ddi=ddsp.GetSpriteTexture(0);
					dds=texman.getname(ddi);
				}
				onpersonicon=dds;
				onpersoniconscale=ddv;
				onpersonicontranslate=(
					!!hdpickup(item)
					&&hdpickup(item).bdroptranslation
				)||(
					!!hdweapon(item)
					&&hdweapon(item).bdroptranslation
				);
			}else onpersonicon="";

			int seli=IndexOf(sel);
			if(seli>=0){
				ddv=(2.,2.4);
				let itemd=inventory(getdefaultbytype((class<actor>)(sel)));
				let hdw=hdweapon(itemd);
				let hdm=hdmagammo(itemd);
				let hds=hdstorageitem(item);
				if(hds){
					subcontainerbulk=FinalNumber(items[seli]);
				}else subcontainerbulk=-1;
				if(hdw){
					string entry=items[seli];
					entry=entry.left(entry.RightIndexOf(","));
					dds=entry.mid(entry.RightIndexOf(",")+1);
				}else if(hdm){
					double scc;
					string gbg1;name gbg2;
					[dds,gbg1,gbg2,scc]=hdm.getmagsprite(FinalNumber(items[seli]));
					ddv*=scc;
				}else if(HDPickup(itemd)){
					swapamt="\cu<->: \cj";
					ddi=itemd.icon;
					if(!!ddi)dds=texman.getname(ddi);
				}
				if(dds==""){
					let ddsp=itemd.spawnstate;
					if(ddsp!=null)ddi=ddsp.GetSpriteTexture(0);
					dds=texman.getname(ddi);
				}
				selectedicon=dds;
				selectediconscale=ddv;
				selectedicontranslate=(
					!!hdpickup(itemd)
					&&hdpickup(itemd).bdroptranslation
				)||(
					!!hdweapon(itemd)
					&&hdweapon(itemd).bdroptranslation
				);
			}else selectedicon="";
		}

		//update the list
		int endi=min(sels,SI_MAXROWS);
		for(int i=0;i<SI_MAXROWS;i++){
			if(i<endi){
				int seli=i+weaponstatus[SISTAT_SELINDEX];
				while(seli>=sels)seli-=sels;

				let thisclassname=selectableitems[seli];
				let thisclass=(class<actor>)(thisclassname);
				selectablenames[i]=(i?"\cg":"\cj")..getdefaultbytype(thisclass).gettag();

				int bps=Count(thisclassname);
				selectablebps[i]=(bps?"\cb":"\cs")..bps;
				int ops=HDWeapon.GetActualAmount(owner,thisclassname);
				if(thisclassname==getclassname())ops--;	//don't count self
				selectableops[i]=(ops?"\cu":"\cm")..ops;
			}else{
				selectablenames[i]="";
			}
		}

	}

	override void DrawHUDStuff(HDStatusBar sb,HDWeapon hdw,HDPlayerPawn hpl){
		sb.beginhud(forcescaled:true);

		int bofs=-120;
		int lnh=SmallFont.GetHeight()+3;

		if(onpersonicon!=""){
			sb.drawimage(onpersonicon,(20,bofs+70),
				sb.DI_SCREEN_CENTER|sb.DI_ITEM_CENTER|(onpersonicontranslate?sb.DI_TRANSLATABLE:0),
				alpha:0.6,
				scale:onpersoniconscale
			);
		}

		if(selectedicon!=""){
			sb.drawimage(selectedicon,(0,bofs+60),
				sb.DI_SCREEN_CENTER|sb.DI_ITEM_CENTER|(selectedicontranslate?sb.DI_TRANSLATABLE:0),
				scale:selectediconscale
			);
		}

		sb.DrawString(sb.pSmallFont, string.format(Stringtable.Localize("$BACKPACK_TOP"),gettag()), (0,bofs), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_CENTER);
		sb.DrawString(sb.pSmallFont, Stringtable.Localize("$BACKPACK_TOTALBULK")..int(itembulk).."\c-", (0,bofs+lnh), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_CENTER);


		bofs+=100;
		for(int i=0;i<SI_MAXROWS;i++){
			if(selectablenames[i]==""){
				if(!i){
					sb.DrawString(sb.pSmallFont,string.format("\cu"..String.Format(StringTable.Localize("$BACKPACK_EMPTY1"),gettag())), (0,-lnh), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_CENTER);
					sb.DrawString(sb.pSmallFont,"\cu"..StringTable.Localize("$BACKPACK_EMPTY2"), (0,0), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_CENTER);
				}
				break;
			}

			bofs+=lnh;
			
			sb.DrawString(sb.pSmallFont, selectablenames[i], (30,bofs), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_RIGHT);

			sb.DrawString(sb.pSmallFont, selectablebps[i], (60,bofs), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_RIGHT);
			sb.DrawString(sb.pSmallFont, selectableops[i], (90,bofs), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_RIGHT);
		}
		if(
			selectableitems.size()>SI_MAXROWS
		)sb.DrawString(sb.pSmallFont,"\cu"..StringTable.Localize("$BACKPACK_SCROLL"), (30,SI_MAXROWS*lnh), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_RIGHT,alpha:((level.time>>3)&(1|2|4))?0.9:0.4);

		if(swapamt!="")sb.DrawString(sb.pSmallFont,swapamt..weaponstatus[SISTAT_HOWMANY], (60,-3*lnh), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_LEFT);
		else if(subcontainerbulk>=0)sb.DrawString(sb.pSmallFont,"\cu"..Stringtable.Localize("$BACKPACK_TOTALBULK").."\cj"..subcontainerbulk, (30,-3*lnh), sb.DI_SCREEN_CENTER | sb.DI_TEXT_ALIGN_LEFT);

	}

	//update amounts
	double ownerbulk;
	override void DoEffect(){
		super.DoEffect();
		if(hdplayerpawn(owner)){
			double ob=hdplayerpawn(owner).enc;
			if(ob!=ownerbulk){
				UpdateHudStuff();
				ownerbulk=ob;
			}
		}
	}

	override void DropOneAmmo(int amt){
		int i=weaponstatus[SISTAT_SELINDEX];
		if(selectableitems.size()>i){
			let iii=selectableitems[i];

			//don't just drop one 9mm at a time
			let iiic=(class<hdpickup>)(iii);
			if(
				iiic
				&&!((class<hdmagammo>)(iii))
			){
				double blk=10;
				let hdp=hdplayerpawn(owner);
				if(hdp)blk*=hdp.heightmult; //big hands = big fistfuls of stuff
				double blk2=max(0.001,hdpickup(getdefaultbytype(iiic)).bulk);
				amt=int(max(1,blk/blk2));
			}

			Extract(IndexOf(iii),amt);
		}
		SanitizeSelectionIndex();
	}

	override bool AddSpareWeapon(actor newowner){
		if(items.size()>0)return false;
		return AddSpareWeaponRegular(newowner);
	}
	override hdweapon GetSpareWeapon(actor newowner,bool reverse,bool doselect){return GetSpareWeaponRegular(newowner,reverse,doselect);}
	override void actualpickup(actor other,bool silent){
		let current=HDStorageItem(other.findinventory(getclass()));
		//add empty backpack under new backpack
		if(
			current
			&&current.items.size()>0
			&&self.items.size()==0
		){
			AddSpareWeapon(other);
			return;
		}
		RecalculateBulk();
		super.actualpickup(other,silent);
	}





	states{
	select:
		TNT1 A 0{
			invoker.UpdateSelected();
		}
		goto super::select;
	ready:
		TNT1 A 1{
			int bt=player.cmd.buttons;
			if(bt&BT_FIREMODE){
				if(JustPressed(BT_ATTACK))invoker.SanitizeSelectionIndex(-1);
				else if(JustPressed(BT_ALTATTACK))invoker.SanitizeSelectionIndex(1);
				else{
					int moveamt=SmoothScroll(
						SISTAT_SCROLL,
						SI_SCROLLCYCLE
					);
					if(moveamt)invoker.SanitizeSelectionIndex(-moveamt);
				}
			}else if(bt&BT_ZOOM){
				int howmany=invoker.weaponstatus[SISTAT_HOWMANY];
				if(JustPressed(BT_ATTACK))howmany--;
				else if(JustPressed(BT_ALTATTACK))howmany++;
				else howmany+=SmoothScroll(
					SISTAT_SCROLL,
					SI_SCROLLCYCLE,
					SISTAT_HOWMANY,
					1,
					100*invoker.maxbunch,
					true
				);
				invoker.weaponstatus[SISTAT_HOWMANY]=clamp(howmany,1,invoker.maxbunch);
			}else{
				A_WeaponReady(WRF_ALL);
				invoker.weaponstatus[SISTAT_SCROLL]=0;
			}
		}goto readyend;
	zoom:
		stop;
	fire:
		TNT1 A 0{
			invoker.SanitizeSelectionIndex(-1);
		}goto nope;
	altfire:
		TNT1 A 0{
			invoker.SanitizeSelectionIndex(1);
		}goto nope;
	reload:
		TNT1 A 2{
			int i=invoker.weaponstatus[SISTAT_SELINDEX];
			if(
					i>=0
					&&invoker.selectableitems.size()>i
				){
				let sss=invoker.selectableitems[i];
				let iii=findinventory(sss);
				if(!!iii){
					invoker.Insert(iii,invoker.weaponstatus[SISTAT_HOWMANY]);
					A_StartSound("weapons/pocket",CHAN_WEAPON);
				}
			}
			invoker.UpdateHudStuff();
		}
		TNT1 AAAAAAAA 1 A_JumpIf(!PressingReload(),"nope");
		goto readyend;
	unload:
		TNT1 A 2{
			int i=invoker.weaponstatus[SISTAT_SELINDEX];
			if(
					i>=0
					&&invoker.selectableitems.size()>i
				){
				let iii=invoker.selectableitems[i];
				let eee=invoker.Extract(invoker.IndexOf(iii),invoker.weaponstatus[SISTAT_HOWMANY]);
				let p=HDPickup(eee);
				let w=HDWeapon(eee);
				if(p)p.ActualPickup(self,true);
				else if(
					w
					&&w.getclass()!=invoker.getclass()	//instaswapping looks REALLY confusing
				){
					w.bno_auto_switch=true;
					w.ActualPickup(self,true);
				}
				//restore any unduly deleted items
				let stillhere=findinventory(iii);
				if(
					!!stillhere
					&&stillhere!=invoker
					&&invoker.selectableitems.Find(iii)==invoker.selectableitems.size()
				){
					invoker.selectableitems.Insert(i,iii);
				}
			}
			invoker.SanitizeSelectionIndex();
		}
		TNT1 AAAAAAAA 1 A_JumpIf(!PressingUnload(),"nope");
		goto readyend;
	altreload:
		TNT1 A 1{
			invoker.DumpItems();
		}
		goto readyend;
	}
}


class HDStorageItemList:Thinker{
	virtual bool CanAdd(
		class<inventory> item
	){return true;}

	array<int> randomizables;

	//compile this list iff no other item of this class found with it
	//return the first item of this class that has a list
	static HDStorageItemList CompileRandomizables(
		class<HDStorageItemList> listclass
	){
		ThinkerIterator it = ThinkerIterator.Create(listclass);
		HDStorageItemList si;
		while(si=HDStorageItemList(it.Next())){
			if(si.randomizables.size()>0)return si;
		}
		si=HDStorageItemList(new(listclass));si.randomizables.clear();

		//populate the list
		for(int i=0;i<allactorclasses.size();i++){
			if(
				allactorclasses[i].IsAbstract()
				||!((class<inventory>)(allactorclasses[i]))
				||!HDMath.ValidRandomItemClass(allactorclasses[i])
				||!si.CanAdd((class<inventory>)(allactorclasses[i]))
			)continue;
			let w=HDWeapon(getdefaultbytype(allactorclasses[i]));
			let p=HDPickup(getdefaultbytype(allactorclasses[i]));
			if(
				(!w&&!p)
				||(w&&w.bnorandombackpackspawn)
				||(p&&p.bnorandombackpackspawn)
			)continue;

			si.randomizables.push(i);
		}
		return si;
	}

	//items that should be a bit rarer despite being loadout-available
	virtual bool KeepItRare(class<inventory> this){
		return
			this is "PortableLiteAmp"	//you can't even cannibalize them for batteries
			||this is "BFG9k"
		;
	}
	static void RandomContents(
		HDStorageItem caller,
		class<HDStorageItemList> listclass,
		double proportion,	//stop filling when you're up to this point
		bool fromloadout
	){
		let si=CompileRandomizables(listclass);
		if(!si||si.randomizables.size()<1)return;
		double addmax=min(
			caller.maxcapacity*proportion,
			caller.maxcapacity-caller.itembulk
		);
		double bulkest=0;
		while(bulkest<addmax){
			double bulkadd=0;

			double allowance=frandom(0,frandom(0,addmax-bulkest));
			class<HDWeapon> w;
			class<HDMagAmmo> m;
			class<HDPickup> p;
			class<HDWeaponGiver> wg;
			class<HDPickupGiver> pg;
			bool rollagain=true;

			while(rollagain){
				class<inventory> addthis=(class<inventory>)(allactorclasses[si.randomizables[random(0,si.randomizables.size()-1)]]);
				if(caller.CanFitInThisContainer(addthis)){
					w=(class<HDWeapon>)(addthis);
					p=(class<HDPickup>)(addthis);
					wg=(class<HDWeaponGiver>)(addthis);
					pg=(class<HDPickupGiver>)(addthis);
					rollagain=(
						(
							//never
							fromloadout
							&&(
								(w&&hd_noloadout.IndexOf(HDWeapon(getdefaultbytype(w)).refid)>=0)
								||(p&&hd_noloadout.IndexOf(HDPickup(getdefaultbytype(p)).refid)>=0)
							)
						)||(
							//rare
							(
								(w&&HDWeapon(getdefaultbytype(w)).refid=="")
								||(p&&HDPickup(getdefaultbytype(p)).refid=="")
								||si.KeepItRare(addthis)	//for stuff that's way too frequent in the pool
							)
							&&random(0,5)
						)
					);
				}
			}

			if(wg){
				let pg=HDWeaponGiver(caller.spawn(wg,caller.pos));
				if(pg){
					let pgg=pg.actualweapon;
					if(!pgg){
						pgg=pg.spawnactualweapon();
						pg.destroy();
					}
					if(pgg){
						bulkadd=pgg.weaponbulk();
						caller.Insert(pgg);
					}
				}
			}else if(pg){
				let pg=HDPickupGiver(caller.spawn(pg,caller.pos));
				if(pg){
					let pgg=pg.actualitem;
					if(!pgg){
						pgg=pg.spawnactualitem();
						pg.destroy();
					}
					if(pgg){
						let mgg=HDMagAmmo(pgg);
						if(mgg)bulkadd=mgg.getmagbulk(mgg.maxperunit);
						else bulkadd=pgg.amount*pgg.bulk;
						caller.Insert(pgg);
					}
				}
			}else if(w){
				let ww=HDWeapon(caller.spawn(w,(32000,32000,0)));
				if(ww){
					bulkadd=ww.weaponbulk();
					caller.Insert(ww);
				}
			}else if(p){
				string toadd=p.getclassname();
				let m=(class<HDMagAmmo>)(p);
				if(m){
					let mm=hdmagammo(getdefaultbytype(m));
					let bbb=mm.getmagbulk(mm.maxperunit);if(!bbb)bbb=1.;
					int amt=int(max(1,allowance/bbb));
					if(mm.refid=="")amt=max(1,random(0,(amt>>1)));
					bulkadd=bbb*amt;
					for(int i=0;i<amt;i++){
						toadd=toadd..","..mm.maxperunit;
					}
				}else{
					let pp=hdpickup(getdefaultbytype(p));
					let bbb=pp.bulk;if(!bbb)bbb=1.;
					int amt=int(max(1,allowance/bbb));
					if(pp.refid=="")amt=max(1,random(0,(amt>>1)));
					bulkadd=bbb*amt;
					toadd=toadd..","..amt;
				}
				caller.Add(toadd);
			}

			if(bulkadd==0)break;
			else bulkest+=bulkadd;
		}
		caller.RecalculateBulk();
	}
}

// Example variant: only grab HDMagAmmos
// needs tweaking to actually literally only allow mags
// (PortableLiteAmp and HDArmour are also HDMagAmmos)
// you can test by editing WildBackpack below
class HDStorageItemListMagsOnly:HDStorageItemList{
	override bool CanAdd(
		class<inventory> item
	){
		return (class<HDMagAmmo>)(item);
	}
}

class HDBackpack:HDStorageItem{
	default{
		+inventory.invbar
		+weapon.wimpy_weapon
		+hdweapon.droptranslation
		+hdweapon.fitsinbackpack
		+hdweapon.alwaysshowstatus
		+hdweapon.ignoreloadoutamount
		+hdweapon.hinderlegs
		Weapon.SelectionOrder 1010;
		Inventory.Icon "BPAKA0";
		Inventory.PickupMessage "$PICKUP_BACKPACK";
		Inventory.PickupSound "weapons/pocket";
		Tag "$TAG_BACKPACK";
		hdweapon.refid "bak";
		hdweapon.wornlayer STRIP_BACKPACK;
		HDStorageItem.maxcapacity 1000;
		HDStorageItem.minbulk 100;
		HDStorageItem.maxbunch 20;

		hdweapon.loadoutcodes "
		\cu use \".\" to add items like \",\" in the loadout,
		\cu e.g., bak.z66nogl.4505; \"???\" adds a few randoms.";
	}
	states(actor){
	spawn:
		BPAK ABC -1 nodelay{
			if(items.size()<1)frame=1;
			else if(target)frame=2;

			if(hd_debug)DumpData();
		}
		stop;
	}
}
//semi-filled backpacks at random
class WildBackpack:IdleDummy replaces Backpack{
		//$Category "Items/Hideous Destructor/Gear"
		//$Title "Backpack (Random Spawn)"
		//$Sprite "BPAKC0"
	override void postbeginplay(){
		super.postbeginplay();
		let aaa=HDBackpack(spawn("HDBackpack",pos,ALLOW_REPLACE));
		HDF.TransferSpecials(self, aaa);
		aaa.RandomContents("HDStorageItemList",frandom(0.1,0.7),false);
//aaa.Add("sevenmilbrass,30");
//aaa.Add("fourmilammo,50");
//aaa.Add("hdbattery,0,0,10");
//let iii=inventory(spawn("LiberatorRifle"));aaa.Insert(iii);
		destroy();
	}
}


